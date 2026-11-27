#!/bin/ksh
# =============================================================
# Script   : os_top_oracle_processes.ksh
# Purpose  : The Oracle processes using the most CPU and memory on
#            this server right now, each mapped back to its database
#            session: SID, user, program, SQL_ID and wait event, so
#            "top" output can be acted on
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c
# Run as   : oracle (connects "/ as sysdba" to each running instance)
# Where    : Each database server
# Changes  : None (read-only)
# Usage    : ./os_top_oracle_processes.ksh [count]      default 10
# Notes    : %CPU from ps is the average over the process lifetime for
#            long-running processes; for a live view also use top -c.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

N=${1:-10}
TMP=/tmp/topora.$$
trap 'rm -f $TMP*' EXIT

# Short sampled CPU: two snapshots of /proc/<pid>/stat 3 seconds apart
ps -eo pid,user,rss,pcpu,args --no-headers | awk '$5 ~ /^(oracle|ora_|asm_)/' > $TMP.ps
for P in $(awk '{print $1}' $TMP.ps); do awk '{print $1, $14 + $15}' /proc/$P/stat 2>/dev/null; done > $TMP.t1
sleep 3
for P in $(awk '{print $1}' $TMP.ps); do awk '{print $1, $14 + $15}' /proc/$P/stat 2>/dev/null; done > $TMP.t2
HZ=$(getconf CLK_TCK)
awk -v hz=$HZ 'FILENAME ~ /t1$/ {a[$1] = $2; next}
               FILENAME ~ /t2$/ {if ($1 in a) cpu[$1] = ($2 - a[$1]) / hz / 3 * 100; next}
               {printf "%s %.1f %d %s %s\n", $1, cpu[$1] + 0, $3 / 1024, $2, substr($0, index($0, $5))}' \
    $TMP.t1 $TMP.t2 $TMP.ps > $TMP.all

echo "=============================================================="
echo "Top Oracle processes on $(hostname)   $(date '+%d-%b-%Y %H:%M')   (CPU over the last 3 s)"
echo "=============================================================="
echo "$(nproc) CPUs, load average: $(cut -d' ' -f1-3 /proc/loadavg)"

show() {   # $1 = sort column (2 = cpu, 3 = MB)  $2 = title
  echo
  echo "$2"
  printf "   %-8s %6s %8s %-8s %s\n" "PID" "CPU%" "RSS MB" "User" "Process"
  sort -k$1 -nr $TMP.all | head -$N | awk '{printf "   %-8s %6s %8s %-8s %s\n", $1, $2, $3, $4, substr($0, index($0, $5), 60)}'
}
show 2 "Top $N by CPU"
show 3 "Top $N by memory (RSS includes shared SGA pages it has touched)"

# Map PIDs to sessions, per instance
echo
echo "Database sessions behind the top CPU processes"
sort -k2 -nr $TMP.all | head -$N > $TMP.top
for SID in $(awk '{p = $5; if (p ~ /^oracle/) {sub("^oracle", "", p); print p} else if (p ~ /^(ora|asm)_..._/) {sub("^(ora|asm)_[a-z0-9]+_", "", p); print p}}' $TMP.top | sort -u); do
  PIDS=$(awk -v s="$SID" '$5 == "oracle" s || $5 ~ "_" s "$" {printf "%s%s", sep, $1; sep = ","}' $TMP.top)
  [ -z "$PIDS" ] && continue
  H=$(awk -F: -v s="$SID" '$1 == s {print $2}' /etc/oratab 2>/dev/null)
  [ -z "$H" ] && H=$(awk -F: -v s="$SID" 'BEGIN {sub(/[0-9]+$/, "", s)} $1 == s {print $2}' /etc/oratab 2>/dev/null)
  H=${H:-$ORACLE_HOME}
  [ -x "$H/bin/sqlplus" ] || { echo "   $SID: Oracle home not found, skipped"; continue; }
  echo
  echo ">> Instance $SID"
  ORACLE_SID=$SID ORACLE_HOME=$H $H/bin/sqlplus -s -L "/ as sysdba" <<SQL
SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF
COLUMN spid     FORMAT a8  HEADING 'OS PID'
COLUMN sess     FORMAT a12 HEADING 'SID,SERIAL#'
COLUMN username FORMAT a14 HEADING 'User'
COLUMN program  FORMAT a28 HEADING 'Program'
COLUMN sql_id   FORMAT a13 HEADING 'SQL_ID'
COLUMN event    FORMAT a30 HEADING 'Event (or CPU)'
COLUMN pga_mb   FORMAT 99,990 HEADING 'PGA MB'
SELECT p.spid, s.sid || ',' || s.serial# AS sess, NVL(s.username, '(background)') AS username,
       SUBSTR(NVL(s.module, s.program), 1, 28) AS program, s.sql_id,
       CASE WHEN s.state = 'WAITING' THEN s.event ELSE 'ON CPU' END AS event,
       ROUND(p.pga_alloc_mem / 1048576) AS pga_mb
FROM   v\$process p LEFT JOIN v\$session s ON s.paddr = p.addr
WHERE  p.spid IN ($(echo $PIDS | sed "s/\([0-9]*\)/'\1'/g"));
EXIT
SQL
done

echo
echo "Look at a SQL_ID in detail with tuning/sql/sql_details.sql <sql_id>."
