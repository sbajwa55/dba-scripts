#!/bin/ksh
# =============================================================
# Script   : dg_broker_check.ksh
# Purpose  : Data Guard broker health in one run: configuration
#            status, every member and its role, VALIDATE DATABASE for
#            each standby (switchover readiness), and an exit code
#            that monitoring tools can use
# Section  : High Availability / Data Guard
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c
#            with the Data Guard broker (dg_broker_start = TRUE)
# Run as   : oracle, with ORACLE_HOME and ORACLE_SID set for a local
#            instance of the primary or a standby (connects with
#            OS authentication "/": no password in the script)
# Where    : Any database server in the configuration
# Changes  : None (read-only: SHOW and VALIDATE commands only)
# Usage    : ./dg_broker_check.ksh            full report
#            ./dg_broker_check.ksh -q         only the summary line
# Exit     : 0 = SUCCESS, 1 = WARNING, 2 = ERROR or broker unreachable
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

QUIET=0; [ "$1" = "-q" ] && QUIET=1
PATH=$ORACLE_HOME/bin:$PATH; export PATH

if [ -z "$ORACLE_HOME" ] || [ -z "$ORACLE_SID" ]; then
  echo "Set ORACLE_HOME and ORACLE_SID first (for example: . oraenv)"; exit 2
fi

dg() { dgmgrl -silent / "$1" 2>&1; }

CONFIG=$(dg "show configuration")
STATUS=$(echo "$CONFIG" | awk '/Configuration Status:/ {getline; print $1; exit}')
[ -z "$STATUS" ] && STATUS=$(echo "$CONFIG" | grep -Eo 'SUCCESS|WARNING|ERROR' | tail -1)

case "$STATUS" in
  SUCCESS) RC=0 ;;
  WARNING) RC=1 ;;
  *)       RC=2 ;;
esac

if [ $QUIET -eq 1 ]; then
  echo "$(hostname) $ORACLE_SID Data Guard broker: ${STATUS:-UNREACHABLE}"
  exit $RC
fi

echo "=============================================================="
echo "Data Guard broker check  $(hostname)  SID $ORACLE_SID  $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="
echo "$CONFIG"

if [ -z "$STATUS" ]; then
  echo
  echo "Could not read the broker configuration. Is dg_broker_start TRUE and a configuration created?"
  exit 2
fi

# Member names: lines like "  orcl_site2 - Physical standby database"
MEMBERS=$(echo "$CONFIG" | awk '/ - (Primary database|Physical standby|Logical standby|Snapshot standby|Far sync)/ {print $1 "|" $0}')

echo "$MEMBERS" | while IFS='|' read NAME LINE; do
  [ -z "$NAME" ] && continue
  echo
  echo "--------------------------------------------------------------"
  echo "Member: $NAME"
  echo "--------------------------------------------------------------"
  dg "show database $NAME" | grep -Ev '^$'
  case "$LINE" in
    *standby*)
      echo
      echo ">> VALIDATE DATABASE $NAME"
      dg "validate database $NAME" | grep -Ev '^$' ;;
  esac
done

echo
echo "Overall status: $STATUS (exit code $RC)"
echo "Look for 'Ready for Switchover: Yes' on the standby you plan to switch to."
echo "ORA-16809/16810 in the status: run 'show database <name> statusreport' in DGMGRL for details."
exit $RC
