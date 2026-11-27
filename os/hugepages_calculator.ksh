#!/bin/ksh
# =============================================================
# Script   : hugepages_calculator.ksh
# Purpose  : Work out the right vm.nr_hugepages for the Oracle SGAs
#            running on this server, and show the current HugePages
#            use, the matching memlock limit, and any instance that
#            is not using HugePages
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash, x86-64); Oracle 19c, 21c
# Run as   : oracle (or root)
# Where    : Each database server, with ALL instances (and ASM) started,
#            because it sizes from the shared memory in use right now
# Changes  : None (read-only: prints the settings to apply)
# Usage    : ./hugepages_calculator.ksh
# Notes    : Same method as Oracle's script in MOS note 401749.1.
#            HugePages cannot be used with MEMORY_TARGET (AMM).
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

HPG_KB=$(awk '/^Hugepagesize/ {print $2}' /proc/meminfo)
[ -z "$HPG_KB" ] && { echo "No Hugepagesize in /proc/meminfo: HugePages not supported here."; exit 1; }

echo "=============================================================="
echo "HugePages calculator on $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="
echo "Current:"
grep -E '^(HugePages_(Total|Free|Rsvd|Surp)|Hugepagesize)' /proc/meminfo | sed 's/^/   /'
echo "   vm.nr_hugepages = $(sysctl -n vm.nr_hugepages 2>/dev/null)"

# Shared memory segments (bytes in column 5 of ipcs -m)
NUM_PG=0; SEGS=0
for SEG_BYTES in $(ipcs -m | awk '$5 ~ /^[0-9]+$/ {print $5}'); do
  MIN_PG=$((SEG_BYTES / (HPG_KB * 1024)))
  if [ $MIN_PG -gt 0 ]; then NUM_PG=$((NUM_PG + MIN_PG + 1)); SEGS=$((SEGS + 1)); fi
done

echo
if [ $NUM_PG -eq 0 ]; then
  echo "No shared memory segments found. Start every instance first (ipcs -m shows them)."
  ls /dev/shm/ora_* >/dev/null 2>&1 && echo "Files /dev/shm/ora_* exist: an instance uses MEMORY_TARGET (AMM), which cannot use HugePages."
  exit 1
fi

echo "Shared memory segments counted : $SEGS"
echo "Recommended vm.nr_hugepages    : $NUM_PG   ($((NUM_PG * HPG_KB / 1024)) MB)"
echo "memlock limit (KB), at least   : $((NUM_PG * HPG_KB))"
echo
echo "Instances and their SGA HugePages use (from each alert log, last startup):"
for A in $(ls ${ORACLE_BASE:-/u01/app/oracle}/diag/rdbms/*/*/trace/alert_*.log /u01/app/grid/diag/asm/+asm/*/trace/alert_+ASM*.log 2>/dev/null); do
  L=$(grep -E 'Per process system memlock|Total Shared Global Region in Large Pages|Large Pages used by this instance' "$A" 2>/dev/null | tail -2 | tr -s ' ' | tr '\n' ' ')
  printf "   %-28s %s\n" "$(basename "$A" .log | sed 's/alert_//')" "${L:-(no large-page lines found)}"
done
echo
echo "Apply (as root), with a small margin for SGA growth:"
echo "   echo 'vm.nr_hugepages = $((NUM_PG + 8))' > /etc/sysctl.d/98-oracle-hugepages.conf && sysctl --system"
echo "   /etc/security/limits.d/oracle.conf:  oracle soft memlock $(((NUM_PG + 8) * HPG_KB))   (same for hard, and for grid)"
echo "Then set use_large_pages=ONLY in each database so it fails to start rather than run without HugePages,"
echo "and restart the instances. Re-run this script whenever an SGA size changes."
