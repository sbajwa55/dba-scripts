#!/bin/ksh
# =============================================================
# Script   : alert_log_scan.ksh
# Purpose  : Scan every database (and ASM) alert log on this server
#            for errors in the last N hours: ORA- and TNS- errors,
#            checkpoint problems, deadlocks, instance terminations
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash, GNU awk/date);
#            Oracle 19c, 21c; RAC and Exadata database servers
# Run as   : oracle (and grid, to read ASM logs owned by grid)
# Where    : Each database server; it finds the alert logs itself
#            under the ADR base ($ORACLE_BASE/diag)
# Changes  : None (read-only)
# Usage    : ./alert_log_scan.ksh [hours]          default 24
#            ORACLE_BASE=/u01/app/oracle ./alert_log_scan.ksh 48
# Notes    : SQL alternative inside the database:
#            general/alert_log_errors.sql
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

HOURS=${1:-24}
BASES="${ORACLE_BASE:-/u01/app/oracle} /u01/app/grid"
SINCE=$(date -d "-$HOURS hours" '+%Y-%m-%dT%H:%M')
PATTERN='ORA-[0-9]+|TNS-[0-9]+|Checkpoint not complete|Deadlock|terminating the instance|Instance terminated|WARNING: inbound connection timed out|Errors in file|Starting ORACLE instance|Shutting down instance'

echo "=============================================================="
echo "Alert log scan on $(hostname), last $HOURS hours (since $SINCE)"
echo "=============================================================="

FOUND=0
for BASE in $BASES; do
  for LOG in $(ls $BASE/diag/rdbms/*/*/trace/alert_*.log $BASE/diag/asm/+asm/*/trace/alert_+ASM*.log 2>/dev/null); do
    FOUND=1
    echo
    echo ">> $LOG"
    awk -v since="$SINCE" -v pat="$PATTERN" '
      /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ]/ {ts=substr($0,1,16); sub(/ /,"T",ts); next}
      ts >= since && $0 ~ pat {
        hits++; line[hits]=ts "  " substr($0,1,200)
        if (match($0, /ORA-[0-9]+/)) code[substr($0,RSTART,RLENGTH)]++
      }
      END {
        if (hits == 0) { print "   no matching lines"; exit }
        print "   Summary by ORA- code:"
        for (c in code) printf "     %-10s %5d\n", c, code[c]
        print "   Last 25 matching lines:"
        start = (hits > 25) ? hits - 24 : 1
        for (i = start; i <= hits; i++) print "     " line[i]
      }' "$LOG"
  done
done

[ $FOUND -eq 0 ] && echo "No alert logs found under $BASES. Set ORACLE_BASE and run again."
echo
echo "ORA-00600 / ORA-07445 are internal errors: check the incident with adrci and open an SR."
echo "Restarts show as 'Starting ORACLE instance' / 'Shutting down instance' lines."
