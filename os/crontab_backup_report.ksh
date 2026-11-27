#!/bin/ksh
# =============================================================
# Script   : crontab_backup_report.ksh
# Purpose  : What runs from cron for the Oracle users and did it
#            work: each active cron entry with its schedule, the log
#            file it writes to, when that log last changed, and any
#            error lines (ORA-, RMAN-, ERROR, failed) in its tail.
#            Also saves a dated copy of each crontab.
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash)
# Run as   : oracle (its own crontab), or root to cover oracle and grid
# Where    : Each database server
# Changes  : Writes a copy of each crontab to SAVE_DIR (default
#            $HOME/crontab_backup). Changes nothing else.
# Usage    : ./crontab_backup_report.ksh
#            SAVE_DIR=/u01/admin/cron ./crontab_backup_report.ksh
# Settings : CRON_USERS (default "oracle grid" as root, else yourself)
# Notes    : Finds the log from a "> file" or ">> file" redirect on the
#            cron line. Jobs that log inside the script are shown as
#            "no redirect": check them by hand.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

SAVE_DIR=${SAVE_DIR:-$HOME/crontab_backup}
STAMP=$(date +%Y%m%d_%H%M)
if [ "$(id -u)" -eq 0 ]; then USERS=${CRON_USERS:-"oracle grid"}; else USERS=$(id -un); fi
mkdir -p "$SAVE_DIR" 2>/dev/null

echo "=============================================================="
echo "Cron jobs on $(hostname)   $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

for U in $USERS; do
  id "$U" >/dev/null 2>&1 || continue
  if [ "$U" = "$(id -un)" ]; then CT=$(crontab -l 2>/dev/null); else CT=$(crontab -l -u "$U" 2>/dev/null); fi
  echo
  echo ">> User $U"
  if [ -z "$CT" ]; then echo "   no crontab"; continue; fi
  echo "$CT" > "$SAVE_DIR/crontab_${U}_$(hostname -s)_$STAMP.txt" && echo "   saved: $SAVE_DIR/crontab_${U}_$(hostname -s)_$STAMP.txt"
  echo "   disabled (commented) jobs: $(echo "$CT" | grep -cE '^[[:space:]]*#[[:space:]]*[0-9*@]')"

  echo "$CT" | grep -vE '^[[:space:]]*(#|$)' | grep -vE '^[A-Z_]+=' | while read -r LINE; do
    case "$LINE" in
      @*) SCHED=$(echo "$LINE" | awk '{print $1}');           CMD=$(echo "$LINE" | cut -d' ' -f2-) ;;
      *)  SCHED=$(echo "$LINE" | awk '{print $1,$2,$3,$4,$5}'); CMD=$(echo "$LINE" | cut -d' ' -f6-) ;;
    esac
    LOG=$(echo "$CMD" | grep -oE '>>?[[:space:]]*[^[:space:]&;|]+' | grep -v '&1' | head -1 | sed 's/^>>*[[:space:]]*//')
    echo
    echo "   [$SCHED]  $(echo "$CMD" | cut -c1-110)"
    if [ -z "$LOG" ] || [ "$LOG" = /dev/null ]; then echo "      log: no redirect (or /dev/null) - check the script's own log"; continue; fi
    case "$LOG" in *'`'*|*'$('*|*'%'*) echo "      log: dated name ($LOG) - check the newest file in its folder"; continue ;; esac
    LOG=$(echo "$LOG" | sed "s|\${HOME}|$HOME|; s|\$HOME|$HOME|")   # expand $HOME only; nothing is executed
    if [ ! -f "$LOG" ]; then echo "      log: $LOG  (not found - has the job ever run?)"; continue; fi
    AGE_H=$(( ($(date +%s) - $(stat -c %Y "$LOG")) / 3600 ))
    ERR=$(tail -200 "$LOG" | grep -E 'ORA-[0-9]+|RMAN-[0-9]+|ERROR|[Ff]ailed|FAILED|No such file|Permission denied' | grep -vE 'RMAN-0(8137|8138|8120)' | tail -3)
    echo "      log: $LOG  (last written $(date -d @$(stat -c %Y "$LOG") '+%d-%b %H:%M'), ${AGE_H} h ago)"
    if [ -n "$ERR" ]; then echo "      ERRORS in last 200 lines:"; echo "$ERR" | cut -c1-120 | sed 's/^/        /'
    else echo "      no error lines in the last 200 lines"; fi
  done
done

echo
echo "A daily job whose log is more than 24 h old has stopped running (check cron, the script path, and the"
echo "environment: cron does not read .bash_profile, so set ORACLE_HOME/ORACLE_SID in the script)."
