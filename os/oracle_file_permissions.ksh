#!/bin/ksh
# =============================================================
# Script   : oracle_file_permissions.ksh
# Purpose  : Security check of Oracle files on this server: owner
#            and setuid bits of the oracle binary, world-writable
#            files in each Oracle home, and the permissions of oratab,
#            oraInst.loc, password files, wallets and network files
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle and Grid 19c, 21c
# Run as   : oracle (root sees every file; other users may get
#            "permission denied" lines, which are reported)
# Where    : Each database server
# Changes  : None (read-only: fixes are printed, never run)
# Usage    : ./oracle_file_permissions.ksh
# Exit     : number of FAIL lines
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

FAILS=0
res() { [ "$1" = FAIL ] && FAILS=$((FAILS + 1)); printf "  %-4s  %-58s %-12s %s\n" "$1" "$2" "$3" "$4"; }
perm()  { stat -c '%a' "$1" 2>/dev/null; }
owner() { stat -c '%U:%G' "$1" 2>/dev/null; }
# world-readable or -writable?  $1 = octal mode
others() { echo "$1" | awk '{print substr($0, length($0), 1)}'; }

echo "=============================================================="
echo "Oracle file permissions on $(hostname) as $(id -un)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

HOMES=$(awk -F: '/^[^#*]/ && NF >= 2 {print $2}' /etc/oratab 2>/dev/null)
INV=$(awk -F= '/^inventory_loc/ {print $2}' /etc/oraInst.loc 2>/dev/null)
[ -f "$INV/ContentsXML/inventory.xml" ] && HOMES="$HOMES $(grep '<HOME ' "$INV/ContentsXML/inventory.xml" | grep -v 'REMOVED="T"' | sed 's/.*LOC="\([^"]*\)".*/\1/')"
HOMES=$(echo $HOMES | tr ' ' '\n' | sort -u)

echo
echo "Central files"
for F in /etc/oratab /etc/oraInst.loc; do
  [ -f "$F" ] || continue
  P=$(perm $F); case $(others $P) in [2367]) R=FAIL ;; *) R=PASS ;; esac
  res $R "$F" "$P" "$(owner $F)  (no write for others)"
done
[ -n "$INV" ] && res INFO "Inventory $INV" "$(perm $INV)" "$(owner $INV)"

for H in $HOMES; do
  [ -d "$H" ] || continue
  echo
  echo "Home $H  ($(owner $H))"
  B=$H/bin/oracle
  if [ -f "$B" ]; then
    P=$(perm $B)
    [ "$P" = 6751 ] && res PASS "bin/oracle setuid/setgid" "$P" "expected 6751" \
                    || res FAIL "bin/oracle setuid/setgid" "$P" "expected 6751: run (as owner) relink or chmod 6751"
  fi
  WW=$(find "$H" -xdev \( -type f -o -type d \) -perm -0002 ! -type l 2>/dev/null | grep -v '/tmp/' | head -20)
  N=$(find "$H" -xdev \( -type f -o -type d \) -perm -0002 ! -type l 2>/dev/null | grep -vc '/tmp/')
  [ "$N" -eq 0 ] && res PASS "world-writable files/dirs" "0" "" || { res FAIL "world-writable files/dirs" "$N" "chmod o-w <file>"; echo "$WW" | sed 's/^/          /'; }
  for F in $(ls $H/dbs/orapw* 2>/dev/null); do
    P=$(perm $F); case $(others $P) in 0) R=PASS ;; *) R=FAIL ;; esac
    res $R "password file $(basename $F)" "$P" "expect 640 or 600 (chmod 640)"
  done
  for F in $H/network/admin/sqlnet.ora $H/network/admin/listener.ora $H/network/admin/tnsnames.ora; do
    [ -f "$F" ] || continue
    P=$(perm $F); case $(others $P) in [2367]) R=FAIL ;; *) R=PASS ;; esac
    res $R "network/admin/$(basename $F)" "$P" "no write for others"
  done
done

echo
echo "Wallets (cwallet.sso / ewallet.p12): should be 600, owned by the software owner"
for W in $(find ${ORACLE_BASE:-/u01/app/oracle} /u01/app/grid /etc/oracle $HOMES -xdev \( -name cwallet.sso -o -name ewallet.p12 \) 2>/dev/null | sort -u); do
  P=$(perm $W); case $P in 600|400) R=PASS ;; 640|440) R=WARN ;; *) R=FAIL ;; esac
  res $R "$W" "$P" "$(owner $W)"
done

echo
echo "FAIL count: $FAILS"
echo "Never chmod -R a whole Oracle home: fix single files, then re-run this check."
exit $FAILS
