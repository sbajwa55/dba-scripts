#!/bin/ksh
# =============================================================
# Script   : ggserr_log_scan.ksh
# Purpose  : Scan the Oracle GoldenGate error log (ggserr.log) for
#            ERROR and WARNING lines, and summarise them by OGG code
# Section  : High Availability / GoldenGate
# Platform : Oracle Linux / RHEL (ksh or bash); GoldenGate 19c, 21c,
#            Classic or Microservices architecture
# Run as   : The OS user that owns GoldenGate (often oracle or ogg)
# Where    : On each GoldenGate hub / server
# Changes  : None (read-only)
# Usage    : ./ggserr_log_scan.ksh [path_to_ggserr.log] [lines]
#              e.g. ./ggserr_log_scan.ksh
#                   ./ggserr_log_scan.ksh /u01/ogg/deployments/src/var/log/ggserr.log 5000
# Finds    : If no path is given it looks in, in order:
#              $OGG_VAR_HOME/log/ggserr.log   (Microservices)
#              $OGG_HOME/ggserr.log, $GG_HOME/ggserr.log (Classic)
#              then searches /u01 and /u02 for ggserr.log files
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

LINES_TO_READ=${2:-3000}

find_logs() {
  if [ -n "$1" ]; then echo "$1"; return; fi
  for f in "$OGG_VAR_HOME/log/ggserr.log" "$OGG_HOME/ggserr.log" "$GG_HOME/ggserr.log"; do
    [ -f "$f" ] && echo "$f"
  done
  find /u01 /u02 -maxdepth 8 -name ggserr.log -type f 2>/dev/null
}

LOGS=$(find_logs "$1" | sort -u)
if [ -z "$LOGS" ]; then
  echo "No ggserr.log found. Pass the path: $0 /path/to/ggserr.log"
  exit 1
fi

for LOG in $LOGS; do
  echo "=============================================================="
  echo "GoldenGate error log : $LOG"
  echo "Last modified        : $(ls -l --time-style='+%d-%b-%Y %H:%M' "$LOG" 2>/dev/null | awk '{print $6, $7}')"
  echo "Lines checked        : last $LINES_TO_READ"
  echo "Host / checked at    : $(hostname) / $(date '+%d-%b-%Y %H:%M')"
  echo "=============================================================="

  ERRS=$(tail -n "$LINES_TO_READ" "$LOG" | grep -E "ERROR|WARNING" )
  if [ -z "$ERRS" ]; then
    echo "No ERROR or WARNING lines found."
    echo
    continue
  fi

  echo
  echo "Count by OGG message code (most frequent first):"
  echo "$ERRS" | grep -oE "OGG-[0-9]{5}" | sort | uniq -c | sort -rn | head -20 \
    | awk '{printf "  %6d  %s\n", $1, $2}'

  echo
  echo "Last 30 ERROR lines:"
  echo "$ERRS" | grep "ERROR" | tail -30 | cut -c1-220

  echo
  echo "Last 15 WARNING lines:"
  echo "$ERRS" | grep "WARNING" | tail -15 | cut -c1-220
  echo
done

echo "Common codes: OGG-01224/01232 network or receiver problem; OGG-00664/00665 database"
echo "login or ORA- error; OGG-01004 aborted grouped transaction; OGG-00446 cannot read redo/trail."
echo "Check process status with the Admin Client or GGSCI: INFO ALL, then LAG <process>."
