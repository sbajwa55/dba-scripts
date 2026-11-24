#!/bin/ksh
# =============================================================
# Script   : db_host_check.ksh
# Purpose  : One-page health check of an Oracle database server:
#            uptime and load, memory and HugePages, file system
#            space, running instances (pmon), listeners, and
#            Exadata image version where present
# Section  : OS
# Platform : Oracle Linux / RHEL 7, 8, 9 (ksh or bash); also works on
#            Exadata database servers
# Run as   : oracle (or grid); root is NOT needed
# Where    : Each database server (each RAC node)
# Changes  : None (read-only)
# Usage    : ./db_host_check.ksh [disk_alert_pct]   default 85
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

DISK_PCT=${1:-85}
line() { echo "--------------------------------------------------------------"; }

echo "=============================================================="
echo "Database host check: $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="
[ -f /etc/os-release ] && grep -E '^PRETTY_NAME' /etc/os-release | cut -d= -f2 | tr -d '"'
echo "Kernel : $(uname -r)"
if [ -x /usr/local/bin/imageinfo ] || [ -x /opt/oracle.cellos/imageinfo ]; then
  echo "Exadata image : $( (/usr/local/bin/imageinfo -ver || /opt/oracle.cellos/imageinfo -ver) 2>/dev/null | head -1)"
fi

line; echo "Uptime and load (load above the number of CPUs means the server is busy)"
uptime
echo "CPUs : $(nproc 2>/dev/null)"

line; echo "Memory (MB)"
free -m
echo
echo "HugePages (Oracle SGA should fit in HugePages; Free close to 0 is normal once instances start)"
grep -E 'HugePages_(Total|Free|Rsvd)|Hugepagesize' /proc/meminfo
if grep -q '\[always\]' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null; then
  echo "WARNING: Transparent HugePages is ENABLED. Oracle recommends disabling it."
fi

line; echo "File systems at or above ${DISK_PCT}% used"
df -hP -x tmpfs -x devtmpfs 2>/dev/null | awk -v p="$DISK_PCT" 'NR==1 {print; next} {u=$5; sub("%","",u); if (u+0 >= p) print}'
echo
echo "Oracle file systems:"
df -hP 2>/dev/null | awk 'NR==1 || /\/u0[0-9]|\/oracle|\/backup|\/arch/'

line; echo "Running instances (pmon)"
ps -eo user,pid,etime,args | grep '[p]mon_' | awk '{printf "  %-10s %-8s up %-14s %s\n", $1, $2, $3, $4}'

line; echo "Listeners"
for L in $(ps -eo args | grep '[t]nslsnr' | awk '{print $2}' | sort -u); do
  echo "  $L"
done
command -v lsnrctl >/dev/null 2>&1 && lsnrctl status 2>/dev/null | grep -E 'Alias|Start Date|Uptime|Service ".*" has' | head -20

line; echo "Top 5 processes by memory"
ps -eo pid,user,rss,args --sort=-rss | head -6 | awk 'NR==1 {print; next} {printf "%-8s %-10s %8.0f MB  %s\n", $1, $2, $3/1024, $4}'

line; echo "Recent OS errors (last 20 lines mentioning error/fail/oom)"
( journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null || dmesg -T 2>/dev/null ) \
  | grep -iE 'error|fail|oom|killed process' | tail -20

echo
echo "Done."
