#!/bin/ksh
# =============================================================
# Script   : oracle_prereq_check.ksh
# Purpose  : Is this Linux server set up the way Oracle needs?
#            Kernel parameters, shell limits of the current user,
#            HugePages and Transparent HugePages, swap, /dev/shm,
#            required RPMs, time sync and SELinux, one PASS/WARN/FAIL
#            line each. Use before an install, upgrade or patch.
# Section  : OS
# Platform : Oracle Linux / RHEL 7, 8, 9 (ksh or bash); Oracle 19c, 21c
# Run as   : oracle, then again as grid (limits are checked for the
#            user running the script). No root needed.
# Where    : Each database server
# Changes  : None (read-only)
# Usage    : ./oracle_prereq_check.ksh
# Exit     : number of FAIL lines (0 = all good)
# Notes    : Minimums follow the Oracle 19c Linux install guide. The
#            oracle-database-preinstall-19c RPM sets most of them.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

FAILS=0
res() {   # $1 PASS/WARN/FAIL  $2 check  $3 found  $4 expected
  [ "$1" = FAIL ] && FAILS=$((FAILS + 1))
  printf "  %-4s  %-34s %-26s %s\n" "$1" "$2" "$3" "$4"
}
ge() { awk -v a="${1:-0}" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }   # works for huge numbers too

echo "=============================================================="
echo "Oracle prerequisites on $(hostname) as $(id -un)   $(date '+%d-%b-%Y %H:%M')"
echo "OS: $(cat /etc/oracle-release /etc/redhat-release 2>/dev/null | head -1)   Kernel: $(uname -r)"
echo "=============================================================="
MEM_KB=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
echo "RAM: $((MEM_KB / 1024 / 1024)) GB"
echo
echo "Kernel parameters"
chk_sysctl() {   # name minimum
  V=$(sysctl -n "$1" 2>/dev/null | awk '{print $1}')
  if ge "$V" "$2"; then res PASS "$1" "$V" ">= $2"; else res FAIL "$1" "${V:-missing}" ">= $2"; fi
}
chk_sysctl fs.file-max 6815744
chk_sysctl fs.aio-max-nr 1048576
chk_sysctl kernel.shmmni 4096
chk_sysctl net.core.rmem_default 262144
chk_sysctl net.core.rmem_max 4194304
chk_sysctl net.core.wmem_default 262144
chk_sysctl net.core.wmem_max 1048576
SHMMAX=$(sysctl -n kernel.shmmax 2>/dev/null)
if ge "$SHMMAX" $((MEM_KB * 1024 / 2)); then res PASS kernel.shmmax "$SHMMAX" ">= half of RAM"; else res FAIL kernel.shmmax "$SHMMAX" ">= half of RAM"; fi
SEM=$(sysctl -n kernel.sem 2>/dev/null | tr -s '\t ' ' ')
set -- $SEM
if ge "$1" 250 && ge "$2" 32000 && ge "$3" 100 && ge "$4" 128; then res PASS kernel.sem "$SEM" ">= 250 32000 100 128"
else res FAIL kernel.sem "$SEM" ">= 250 32000 100 128"; fi
PR=$(sysctl -n net.ipv4.ip_local_port_range 2>/dev/null | tr -s '\t ' ' ')
set -- $PR
if [ "${1:-0}" -le 9000 ] && ge "$2" 65500; then res PASS ip_local_port_range "$PR" "9000 65500"; else res WARN ip_local_port_range "$PR" "9000 65500"; fi
V=$(sysctl -n kernel.panic_on_oops 2>/dev/null)
[ "$V" = 1 ] && res PASS kernel.panic_on_oops "$V" "1" || res WARN kernel.panic_on_oops "$V" "1"

echo
echo "Shell limits for $(id -un) (soft / hard)"
lim() {   # label soft_opt soft_min hard_min
  S=$(ulimit -S$2); H=$(ulimit -H$2)
  [ "$S" = unlimited ] && S=999999999; [ "$H" = unlimited ] && H=999999999
  if ge "$S" $3 && ge "$H" $4; then R=PASS; else R=FAIL; fi
  res $R "$1" "$(ulimit -S$2) / $(ulimit -H$2)" ">= $3 / $4"
}
lim "open files (nofile)" n 1024 65536
lim "processes (nproc)" u 2047 16384
lim "stack (KB)" s 10240 32768
MEMLOCK=$(ulimit -l)
HP_TOTAL=$(awk '/^HugePages_Total/ {print $2}' /proc/meminfo)
HP_SIZE=$(awk '/^Hugepagesize/ {print $2}' /proc/meminfo)
HP_KB=$((HP_TOTAL * HP_SIZE))
if [ "$MEMLOCK" = unlimited ] || ge "$MEMLOCK" $HP_KB; then res PASS "memlock (KB)" "$MEMLOCK" ">= HugePages ($HP_KB KB)"
else res FAIL "memlock (KB)" "$MEMLOCK" ">= HugePages ($HP_KB KB)"; fi

echo
echo "Memory"
if [ "${HP_TOTAL:-0}" -gt 0 ]; then res PASS "HugePages configured" "$HP_TOTAL x ${HP_SIZE} KB" "size with hugepages_calculator.ksh"
else res WARN "HugePages configured" "0" "recommended for SGA > 8 GB"; fi
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
case "$THP" in *"[never]"*) res PASS "Transparent HugePages" "never" "never" ;; *) res FAIL "Transparent HugePages" "$THP" "never (Oracle recommends off)" ;; esac
SWAP_KB=$(awk '/^SwapTotal/ {print $2}' /proc/meminfo)
if [ $MEM_KB -le 16777216 ]; then NEED=$MEM_KB; else NEED=16777216; fi
if ge "$SWAP_KB" $NEED; then res PASS "swap" "$((SWAP_KB / 1024)) MB" ">= $((NEED / 1024)) MB"; else res WARN "swap" "$((SWAP_KB / 1024)) MB" ">= $((NEED / 1024)) MB"; fi
SHM=$(df -k /dev/shm 2>/dev/null | awk 'NR == 2 {print $2}')
res INFO "/dev/shm size" "$((${SHM:-0} / 1024)) MB" "must exceed MEMORY_TARGET if AMM is used"

echo
echo "Required packages"
MISSING=""
command -v rpm >/dev/null 2>&1 || { res WARN "RPMs" "rpm not available" "not an RPM-based system"; MISSING=SKIP; }
[ "$MISSING" = SKIP ] || for P in bc binutils elfutils-libelf fontconfig glibc glibc-devel ksh libaio libaio-devel libgcc \
         libnsl libstdc++ libstdc++-devel libX11 libXau libxcb libXi libXrender libXtst make \
         net-tools nfs-utils policycoreutils smartmontools sysstat unzip; do
  rpm -q "$P" >/dev/null 2>&1 || MISSING="$MISSING $P"
done
[ "$MISSING" = SKIP ] || { [ -z "$MISSING" ] && res PASS "RPMs" "all present" "" || res FAIL "RPMs missing" "$MISSING" "dnf install <name>"; }
rpm -qa 2>/dev/null | grep -q '^oracle-database-preinstall' && res PASS "preinstall RPM" "$(rpm -qa | grep '^oracle-database-preinstall' | head -1)" "" \
                                                     || res WARN "preinstall RPM" "not installed" "oracle-database-preinstall-19c"

echo
echo "Other"
if systemctl is-active chronyd >/dev/null 2>&1 || systemctl is-active ntpd >/dev/null 2>&1; then res PASS "time sync" "chronyd/ntpd active" ""
else res FAIL "time sync" "not running" "chronyd (RAC: or CTSS)"; fi
SEL=$(getenforce 2>/dev/null)
case "$SEL" in Enforcing) res WARN SELinux "$SEL" "supported, but check policies" ;; *) res PASS SELinux "${SEL:-n/a}" "" ;; esac
systemctl is-active avahi-daemon >/dev/null 2>&1 && res WARN "avahi-daemon" "running" "disable on RAC nodes" || res PASS "avahi-daemon" "not running" ""

echo
echo "FAIL count: $FAILS"
echo "Fix kernel parameters in /etc/sysctl.d/97-oracle-database-sysctl.conf (then sysctl --system);"
echo "fix limits in /etc/security/limits.d/oracle-database-preinstall-19c.conf (log in again to apply)."
exit $FAILS
