#!/bin/ksh
# =============================================================
# Script   : crs_asm_status.ksh
# Purpose  : Clusterware (CRS) and ASM health on a RAC / Exadata
#            node: cluster check, resources not ONLINE, database and
#            listener status, voting disks, ASM disk group space, and
#            recent errors in the CRS and ASM alert logs
# Section  : High Availability / RAC
# Platform : Oracle Linux / RHEL; Grid Infrastructure 19c, 21c
# Run as   : The Grid owner (often grid) with the Grid environment set
#            (ORACLE_HOME = Grid home, ORACLE_SID = +ASMn).
#            Some checks also work as oracle; they are skipped if a
#            command is not found.
# Where    : Any one cluster node (cluster checks cover all nodes;
#            log checks cover this node only)
# Changes  : None (read-only: status and list commands only)
# Usage    : ./crs_asm_status.ksh [hours_of_log_to_check]   default 24
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

HOURS=${1:-24}
GRID_HOME=${GRID_HOME:-$ORACLE_HOME}
PATH=$GRID_HOME/bin:$PATH
export PATH

line() { echo "--------------------------------------------------------------"; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "=============================================================="
echo "CRS / ASM status on $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "Grid home: $GRID_HOME"
echo "=============================================================="

if have crsctl; then
  line; echo "Cluster stack on all nodes"
  crsctl check cluster -all 2>&1

  line; echo "Resources NOT fully ONLINE (blank = all ONLINE)"
  crsctl stat res -t 2>/dev/null | awk '
    /^[a-z]/ {res=$1}
    /OFFLINE|INTERMEDIATE|UNKNOWN/ && res !~ /ora\.(gsd|.*\.ons)/ {print "  " res ": " $0}'

  line; echo "Voting disks"
  crsctl query css votedisk 2>&1
else
  echo "crsctl not found: set ORACLE_HOME to the Grid home and run as the grid user."
fi

if have srvctl; then
  line; echo "Databases registered with Clusterware"
  for DB in $(srvctl config database 2>/dev/null); do
    srvctl status database -d "$DB" -v 2>&1
  done
  line; echo "Listeners"
  srvctl status listener 2>&1
  srvctl status scan_listener 2>&1
fi

if have asmcmd; then
  line; echo "ASM disk groups (Usable_file_MB is what you can really use)"
  asmcmd lsdg 2>&1 | awk 'NR==1 || /MOUNTED/'
  echo
  echo "Disk groups over 80% used:"
  asmcmd lsdg --suppressheader 2>/dev/null | awk '
    {total=$(NF-6); free=$(NF-5); name=$NF; if (total>0) {pct=100*(total-free)/total;
     if (pct>=80) printf "  %-12s %5.1f%% used\n", name, pct}}'
fi

line; echo "Errors in the last $HOURS hours: CRS and ASM alert logs on this node"
BASE=${ORACLE_BASE:-/u01/app/grid}
SINCE=$(date -d "-$HOURS hours" '+%Y-%m-%dT%H:%M' 2>/dev/null)
for LOG in $(ls $BASE/diag/crs/*/crs/trace/alert.log $BASE/diag/asm/+asm/*/trace/alert_+ASM*.log 2>/dev/null); do
  echo
  echo ">> $LOG"
  # ASM: 2026-11-24T13:05:12.123-05:00   CRS: 2026-11-24 13:05:12.123 [CRSD(...)]
  awk -v since="$SINCE" '
    /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ]/ {ts=substr($0,1,16); sub(/ /,"T",ts)}
    ts >= since && /ORA-|CRS-[0-9]+|ERROR|error|evict|reboot|offline/ {print "  " ts "  " substr($0,1,180)}
  ' "$LOG" | tail -40
done
echo
echo "Done. Exadata: also check cell health with ExaCHK, or as celladmin: cellcli -e list alerthistory"
