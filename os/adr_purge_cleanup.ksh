#!/bin/ksh
# =============================================================
# Script   : adr_purge_cleanup.ksh
# Purpose  : Space used by every ADR home on this server (database,
#            ASM, listener, CRS): trace, incident, core dump and alert
#            files, and how much is older than N days. With -delete it
#            purges the old files through ADRCI.
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle and Grid 19c, 21c
# Run as   : oracle (and grid for the ASM, CRS and grid listener homes)
# Where    : Each database server
# Changes  : Report only by default. With -delete it MAKES CHANGES:
#            removes trace, incident, cdump and HM files older than N
#            days with "adrci purge" (the current alert log is kept).
# Usage    : ./adr_purge_cleanup.ksh [days]             report, default 30
#            ./adr_purge_cleanup.ksh -delete [days]     purge files older than days
# Notes    : Keep incidents you still need for an open Oracle SR:
#            package them first (adrci> ips pack incident <id>).
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

DELETE=0
[ "$1" = "-delete" ] && { DELETE=1; shift; }
DAYS=${1:-30}
MINUTES=$((DAYS * 24 * 60))
BASES="${ORACLE_BASE:-/u01/app/oracle} /u01/app/grid"

ADRCI=$(command -v adrci 2>/dev/null)
[ -z "$ADRCI" ] && [ -x "$ORACLE_HOME/bin/adrci" ] && ADRCI=$ORACLE_HOME/bin/adrci

echo "=============================================================="
echo "ADR space on $(hostname), files older than $DAYS days   $(date '+%d-%b-%Y %H:%M')"
[ $DELETE -eq 1 ] && echo "MODE: DELETE (purging files older than $DAYS days)" || echo "MODE: report only (add -delete to purge)"
echo "=============================================================="
printf "%-55s %8s %8s %8s %8s %10s\n" "ADR home" "Total MB" "Trace" "Incident" "Cdump" "Old files"

TOTAL=0
for BASE in $BASES; do
  [ -d "$BASE/diag" ] || continue
  for H in $(ls -d $BASE/diag/*/*/* 2>/dev/null); do
    [ -d "$H/trace" ] || continue
    T=$(du -sm "$H" 2>/dev/null | awk '{print $1}')
    TR=$(du -sm "$H/trace" 2>/dev/null | awk '{print $1}')
    IN=$(du -sm "$H/incident" 2>/dev/null | awk '{print $1}')
    CD=$(du -sm "$H/cdump" 2>/dev/null | awk '{print $1}')
    OLD=$(find "$H/trace" "$H/incident" "$H/cdump" -type f -mtime +$DAYS 2>/dev/null | wc -l)
    TOTAL=$((TOTAL + ${T:-0}))
    printf "%-55s %8s %8s %8s %8s %10s\n" "${H#$BASE/}" "${T:-0}" "${TR:-0}" "${IN:-0}" "${CD:-0}" "$OLD"

    if [ $DELETE -eq 1 ]; then
      if [ -z "$ADRCI" ]; then
        echo "   adrci not found (set ORACLE_HOME): skipped"
      elif [ ! -w "$H/trace" ]; then
        echo "   not writable by $(id -un): run as the owner ($(stat -c %U "$H/trace"))"
      else
        for TYPE in TRACE INCIDENT CDUMP HM UTSCDMP; do
          "$ADRCI" exec="set base $BASE; set homepath ${H#$BASE/}; purge -age $MINUTES -type $TYPE" >/dev/null 2>&1
        done
        echo "   purged; now $(du -sm "$H" 2>/dev/null | awk '{print $1}') MB"
      fi
    fi
  done
done

echo
echo "Total ADR space: ${TOTAL} MB"
df -h $BASES 2>/dev/null | sed 's/^/   /'
echo
echo "Make it automatic: ADRCI keeps files for SHORTP_POLICY (traces, default 720 h = 30 days) and"
echo "LONGP_POLICY (incidents, default 8760 h = 1 year). Change per home with, for example:"
echo "   adrci exec=\"set homepath <home>; set control (SHORTP_POLICY=360, LONGP_POLICY=2160)\""
echo "Very large *.trc files that keep growing usually mean an event or trace is switched on."
