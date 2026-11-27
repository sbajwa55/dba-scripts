#!/bin/ksh
# =============================================================
# Script   : oracle_inventory_report.ksh
# Purpose  : What Oracle software is on this server: every Oracle
#            home in the central inventory with its version, owner
#            and applied patches; the databases in /etc/oratab and
#            whether each is running; and the listeners running
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle and Grid 19c, 21c
# Run as   : oracle (OPatch for a grid home may need the grid user)
# Where    : Each database server
# Changes  : None (read-only)
# Usage    : ./oracle_inventory_report.ksh          with patch lists
#            ./oracle_inventory_report.ksh -short   homes only (fast)
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

SHORT=0; [ "$1" = "-short" ] && SHORT=1

echo "=============================================================="
echo "Oracle inventory on $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

INV=$(awk -F= '/^inventory_loc/ {print $2}' /etc/oraInst.loc 2>/dev/null)
echo "Central inventory: ${INV:-not found (/etc/oraInst.loc missing)}"

HOMES=""
if [ -f "$INV/ContentsXML/inventory.xml" ]; then
  HOMES=$(grep '<HOME ' "$INV/ContentsXML/inventory.xml" | grep -v 'REMOVED="T"' | sed 's/.*LOC="\([^"]*\)".*/\1/')
fi
# Add homes from oratab that are not in the inventory
for H in $(awk -F: '/^[^#*]/ && NF >= 2 {print $2}' /etc/oratab 2>/dev/null); do
  echo "$HOMES" | grep -qx "$H" || HOMES="$HOMES
$H"
done

echo
echo "Oracle homes"
for H in $(echo "$HOMES" | sort -u); do
  [ -d "$H" ] || { echo "   $H   (in inventory but directory missing)"; continue; }
  OWNER=$(stat -c %U "$H" 2>/dev/null)
  if [ -x "$H/bin/crsctl" ]; then KIND="Grid"; elif [ -x "$H/bin/oracle" ]; then KIND="Database";
  elif [ -d "$H/OPatch" ]; then KIND="Client/other"; else KIND="Other"; fi
  VER=$("$H/bin/sqlplus" -v 2>/dev/null | awk '/Release|Version/ {v = $NF} END {print v}')
  echo
  printf "   %-50s %-12s owner %-8s version %s\n" "$H" "$KIND" "$OWNER" "${VER:-?}"
  if [ $SHORT -eq 0 ] && [ -x "$H/OPatch/opatch" ]; then
    "$H/OPatch/opatch" lspatches -oh "$H" 2>/dev/null | grep -E '^[0-9]+;' | head -15 | sed 's/^/      patch /'
    [ $? -ne 0 ] && echo "      (opatch could not read this home as $(id -un))"
  fi
done

echo
echo "Databases in /etc/oratab"
printf "   %-14s %-50s %-9s %s\n" "SID" "Home" "Autostart" "Running"
awk -F: '/^[^#*]/ && NF >= 2 {print $1, $2, $3}' /etc/oratab 2>/dev/null | while read SID H AUTO; do
  if ps -eo args | grep -Eq "^(ora|asm)_pmon_${SID}[0-9]*$"; then RUN=YES; else RUN=no; fi
  printf "   %-14s %-50s %-9s %s\n" "$SID" "$H" "$AUTO" "$RUN"
done

echo
echo "Running instances not in /etc/oratab"
ps -eo args | awk '$1 ~ /^(ora|asm)_pmon_/ {sub("^(ora|asm)_pmon_", "", $1); print $1}' | sort -u | while read SID; do
  awk -F: -v s="$SID" '$1 == s {f = 1} END {exit !f}' /etc/oratab 2>/dev/null || \
  awk -F: -v s="$SID" 'BEGIN {sub(/[0-9]+$/, "", s)} $1 == s {f = 1} END {exit !f}' /etc/oratab 2>/dev/null || echo "   $SID"
done

echo
echo "Listeners running"
ps -eo user,args | awk '/tnslsn[r]/ {print "   " $1 "  " $2 "  " $3}' | sort -u

echo
echo "Compare patch levels between nodes and with the standby: the RU should match everywhere."
