#!/bin/ksh
# =============================================================
# Script   : oswatcher_check.ksh
# Purpose  : Is OS data being collected for Oracle Support? Checks
#            that OSWatcher (standalone or inside AHF/TFA) or Exadata
#            ExaWatcher is running, how fresh its newest files are,
#            how far back the archive goes, and its disk use
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); OSWatcher 8.x, AHF 2x.x,
#            Exadata ExaWatcher
# Run as   : oracle, grid or root (to read the AHF repository)
# Where    : Each database server (and Exadata storage cells for
#            ExaWatcher)
# Changes  : None (read-only)
# Usage    : ./oswatcher_check.ksh [archive_dir]
# Exit     : 0 = collecting, 1 = data is stale, 2 = nothing running
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

STALE_MIN=${STALE_MIN:-15}
RC=0

echo "=============================================================="
echo "OS data collection on $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

echo "Processes:"
PS=$(ps -eo user,pid,etime,args | grep -E 'OSWatcher|oswbb|ExaWatcher|tfactl|tfamain|ahf' | grep -v grep)
if [ -z "$PS" ]; then echo "   none found: OSWatcher / AHF / ExaWatcher is NOT running"; RC=2
else echo "$PS" | awk '{printf "   %-8s pid %-7s up %-12s %s\n", $1, $2, $3, substr($0, index($0, $4), 90)}'; fi

# Archive directories to check
ARCH="$1"
[ -z "$ARCH" ] && ARCH=$(ls -d /opt/oracle.ahf/data/repository/suptools/*/oswbb/*/archive \
                              /u01/app/*/oracle.ahf/data/repository/suptools/*/oswbb/*/archive \
                              /u01/app/grid/oracle.ahf/data/*/diag/tfa/../../repository/suptools/*/oswbb/*/archive \
                              /opt/oracle.oswatcher/osw/archive /*/oswbb/archive /*/*/oswbb/archive \
                              /opt/oracle.ExaWatcher/archive 2>/dev/null | sort -u)
echo
if [ -z "$ARCH" ]; then
  echo "No OSWatcher/ExaWatcher archive directory found. Pass it as the first argument."
  [ $RC -lt 2 ] && RC=2
fi

NOW=$(date +%s)
for A in $ARCH; do
  echo "Archive: $A   ($(du -sh "$A" 2>/dev/null | awk '{print $1}'), filesystem $(df -P "$A" | awk 'NR == 2 {print $5}') used)"
  printf "   %-22s %-20s %-20s %s\n" "Collector" "Oldest file" "Newest file" "Age of newest"
  for D in $(ls -d "$A"/*/ 2>/dev/null); do
    NEW=$(ls -t "$D" 2>/dev/null | head -1); OLD=$(ls -tr "$D" 2>/dev/null | head -1)
    [ -z "$NEW" ] && continue
    T=$(stat -c %Y "$D/$NEW"); AGE=$(( (NOW - T) / 60 ))
    FLAG=""; [ $AGE -gt $STALE_MIN ] && { FLAG="  STALE"; [ $RC -lt 1 ] && RC=1; }
    printf "   %-22s %-20s %-20s %s min%s\n" "$(basename "$D")" "$(date -d @$(stat -c %Y "$D/$OLD") '+%d-%b %H:%M')" \
           "$(date -d @$T '+%d-%b %H:%M')" "$AGE" "$FLAG"
  done
done

if command -v tfactl >/dev/null 2>&1; then
  echo
  echo "AHF / TFA:"
  tfactl status 2>/dev/null | sed 's/^/   /' | head -15
  tfactl toolstatus 2>/dev/null | grep -i oswbb | sed 's/^/   /'
fi

echo
case $RC in
  0) echo "Collecting normally." ;;
  1) echo "Some collectors are older than $STALE_MIN minutes: restart OSWatcher (AHF: tfactl start oswbb)." ;;
  2) echo "Not collecting. Install AHF (includes OSWatcher) from MOS note 2550798.1, or start OSWatcher:" 
     echo "   nohup ./startOSWbb.sh 30 48 gzip /path/archive &     (30 s samples, keep 48 hours)" ;;
esac
exit $RC
