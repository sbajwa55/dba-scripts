#!/bin/ksh
# =============================================================
# Script   : audit_file_cleanup.ksh
# Purpose  : Operating-system audit files (.aud / .xml) written by
#            every database and ASM instance: how many, how big, how
#            many are older than N days, and inode usage of each
#            filesystem. With -delete it removes the old files.
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle and Grid 19c, 21c
# Run as   : oracle (and grid for ASM audit files)
# Where    : Each database server
# Changes  : Report only by default. With -delete it MAKES CHANGES:
#            deletes *.aud and *.xml audit files older than N days.
# Usage    : ./audit_file_cleanup.ksh [days]              report, default 30
#            ./audit_file_cleanup.ksh -delete [days]      delete older files
#            AUDIT_DIRS="/u01/app/oracle/admin/ORCL/adump" ./audit_file_cleanup.ksh
# Notes    : Check your company's audit-retention rules first; some
#            require these files to be archived, not deleted.
#            Unified auditing stores records in the database
#            (DBMS_AUDIT_MGMT), not in these files.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

DELETE=0
[ "$1" = "-delete" ] && { DELETE=1; shift; }
DAYS=${1:-30}
OB=${ORACLE_BASE:-/u01/app/oracle}

# Usual audit_file_dest locations, plus every Oracle home in /etc/oratab
DIRS="$AUDIT_DIRS $(ls -d $OB/admin/*/adump /u01/app/grid/admin/*/adump 2>/dev/null)"
for H in $(awk -F: '/^[^#*]/ && NF >= 2 {print $2}' /etc/oratab 2>/dev/null | sort -u); do
  DIRS="$DIRS $H/rdbms/audit"
done

echo "=============================================================="
echo "Audit files on $(hostname), older than $DAYS days   $(date '+%d-%b-%Y %H:%M')"
[ $DELETE -eq 1 ] && echo "MODE: DELETE" || echo "MODE: report only (add -delete to remove old files)"
echo "=============================================================="
printf "%-50s %10s %10s %10s\n" "Directory" "Files" "Size MB" "Older"

for D in $(echo $DIRS | tr ' ' '\n' | sort -u); do
  [ -d "$D" ] || continue
  N=$(find "$D" -maxdepth 1 -type f \( -name '*.aud' -o -name '*.xml' \) 2>/dev/null | wc -l)
  MB=$(du -sm "$D" 2>/dev/null | awk '{print $1}')
  OLD=$(find "$D" -maxdepth 1 -type f \( -name '*.aud' -o -name '*.xml' \) -mtime +$DAYS 2>/dev/null | wc -l)
  printf "%-50s %10s %10s %10s\n" "$D" "$N" "$MB" "$OLD"
  if [ $DELETE -eq 1 ] && [ "$OLD" -gt 0 ]; then
    if [ -w "$D" ]; then
      find "$D" -maxdepth 1 -type f \( -name '*.aud' -o -name '*.xml' \) -mtime +$DAYS -delete 2>/dev/null
      echo "   deleted $OLD file(s)"
    else
      echo "   not writable by $(id -un): run as $(stat -c %U "$D")"
    fi
  fi
done

echo
echo "Inode use (100% = no new files can be created, even with free space):"
df -i $(echo $DIRS | tr ' ' '\n' | xargs -r -n1 sh -c '[ -d "$0" ] && echo "$0"' 2>/dev/null) 2>/dev/null | awk 'NR == 1 || !seen[$1]++' | sed 's/^/   /'
echo
echo "Run it daily from cron, for example:"
echo "   15 2 * * * /path/audit_file_cleanup.ksh -delete 30 > /tmp/audit_cleanup.log 2>&1"
