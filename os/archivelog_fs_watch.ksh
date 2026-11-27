#!/bin/ksh
# =============================================================
# Script   : archivelog_fs_watch.ksh
# Purpose  : Early warning before archive logs fill up and the
#            database hangs: for every running instance, the local
#            archive destinations and Fast Recovery Area with % used
#            (FRA quota and the filesystem underneath), against
#            WARN/CRIT thresholds, with an exit code for monitoring
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c
# Run as   : oracle (connects "/ as sysdba" with OS authentication)
# Where    : Each database server
# Changes  : None (read-only)
# Usage    : ./archivelog_fs_watch.ksh
#            WARN=75 CRIT=85 ./archivelog_fs_watch.ksh
# Exit     : 0 = all below WARN, 1 = WARN, 2 = CRIT
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

WARN=${WARN:-80}
CRIT=${CRIT:-90}
RC=0

TMP=/tmp/archfs.$$
trap 'rm -f $TMP' EXIT

# Print one result line and raise the exit code (no subshells, so RC sticks)
report() {   # $1 = label  $2 = location  $3 = percent used  $4 = extra text
  if   [ -z "$3" ];           then L="cannot read"
  elif [ "$3" -ge "$CRIT" ];  then L=CRIT; [ $RC -lt 2 ] && RC=2
  elif [ "$3" -ge "$WARN" ];  then L=WARN; [ $RC -lt 1 ] && RC=1
  else L=OK; fi
  printf "   %-20s %-30s %4s%% used  %-6s %s\n" "$1" "$2" "${3:-?}" "$L" "$4"
}

echo "=============================================================="
echo "Archive log space on $(hostname)   WARN ${WARN}%  CRIT ${CRIT}%   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

SIDS=$(ps -eo args | awk '$1 ~ /^ora_pmon_/ {sub("ora_pmon_", "", $1); print $1}' | sort -u)
[ -z "$SIDS" ] && { echo "No running database instances found."; exit 0; }

for SID in $SIDS; do
  HOME_=$(awk -F: -v s="$SID" '$1 == s {print $2}' /etc/oratab 2>/dev/null)
  [ -z "$HOME_" ] && HOME_=$(awk -F: -v s="${SID%[0-9]}" '$1 == s {print $2}' /etc/oratab 2>/dev/null)
  [ -z "$HOME_" ] && HOME_=$ORACLE_HOME
  [ -x "$HOME_/bin/sqlplus" ] || { echo; echo ">> $SID: Oracle home not found in /etc/oratab, skipped"; continue; }

  OUT=$(ORACLE_SID=$SID ORACLE_HOME=$HOME_ $HOME_/bin/sqlplus -s -L "/ as sysdba" <<'SQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 300 TRIMSPOOL ON
SELECT 'FRA|' || name || '|' || ROUND(space_limit/1048576) || '|' ||
       ROUND((space_used - space_reclaimable)/NULLIF(space_limit,0)*100)
FROM   v$recovery_file_dest WHERE space_limit > 0;
SELECT 'DEST|' || dest_name || '|' || destination
FROM   v$archive_dest
WHERE  status = 'VALID' AND target = 'PRIMARY' AND destination IS NOT NULL
AND    destination NOT LIKE 'USE_DB_RECOVERY_FILE_DEST%';
SELECT 'MODE|' || log_mode FROM v$database;
EXIT
SQL
)
  echo
  echo ">> Instance $SID"
  echo "$OUT" | grep -q 'ORA-' && { echo "   $(echo "$OUT" | grep -m1 ORA-)"; RC=2; continue; }
  echo "$OUT" | grep -q 'MODE|NOARCHIVELOG' && echo "   NOARCHIVELOG mode: no archive logs are written"

  echo "$OUT" | grep -E '^(FRA|DEST)\|' > $TMP
  while IFS='|' read KIND NAME VAL PCT; do
    if [ "$KIND" = "FRA" ]; then
      report "FRA quota" "$NAME" "$PCT" "(${VAL} MB limit, after reclaimable)"
      DIR=$NAME; LABEL="FRA disk"
    else
      DIR=$VAL; LABEL=$NAME
    fi
    case "$DIR" in
      +*) [ "$KIND" = "DEST" ] && printf "   %-20s %-30s ASM disk group: check ha/rac/asm_diskgroup_health.sql\n" "$LABEL" "$DIR" ;;
      *)  report "$LABEL" "$DIR" "$(df -P "$DIR" 2>/dev/null | awk 'NR == 2 {sub("%", "", $5); print $5}')" "filesystem" ;;
    esac
  done < $TMP
done

echo
echo "When the FRA fills: back up and delete archive logs (RMAN: BACKUP ARCHIVELOG ALL DELETE INPUT;),"
echo "or raise db_recovery_file_dest_size if the disk has room. Never delete archive logs with rm."
exit $RC
