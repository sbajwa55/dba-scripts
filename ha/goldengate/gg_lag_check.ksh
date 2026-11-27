#!/bin/ksh
# =============================================================
# Script   : gg_lag_check.ksh
# Purpose  : GoldenGate process check for monitoring: every Extract,
#            Replicat and the Manager with status, lag and time since
#            checkpoint, flagged against thresholds, with an exit code
# Section  : High Availability / GoldenGate
# Platform : Oracle Linux / RHEL (ksh or bash); GoldenGate 19c, 21c
#            Classic (runs GGSCI itself) or Microservices (reads
#            saved "info all" output from Admin Client)
# Run as   : The OS user that owns GoldenGate (often oracle or ogg)
# Where    : On each GoldenGate server / hub
# Changes  : None (read-only: INFO ALL only)
# Usage    : ./gg_lag_check.ksh                   Classic: uses $GG_HOME/ggsci
#            ./gg_lag_check.ksh /tmp/info_all.txt Microservices: parse saved output
#            LAG_WARN_MIN=5 ./gg_lag_check.ksh    change a threshold
# Settings : LAG_WARN_MIN   (default 10) lag at checkpoint, minutes
#            CHKPT_WARN_MIN (default 15) time since checkpoint, minutes
# Exit     : 0 = all RUNNING within thresholds, 1 = lag over threshold,
#            2 = a process is ABENDED or STOPPED, or GGSCI not found
# Notes    : Microservices: in Admin Client run CONNECT ... then
#            INFO ALL, and save the output to a file (no password is
#            ever kept in this script).
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

LAG_WARN_MIN=${LAG_WARN_MIN:-10}
CHKPT_WARN_MIN=${CHKPT_WARN_MIN:-15}
GG_HOME=${GG_HOME:-$OGG_HOME}

if [ -n "$1" ]; then
  [ -f "$1" ] || { echo "File not found: $1"; exit 2; }
  OUT=$(cat "$1"); SRC="$1"
else
  if [ ! -x "$GG_HOME/ggsci" ]; then
    echo "GGSCI not found. Set GG_HOME to the GoldenGate home, or pass a saved INFO ALL output file."
    exit 2
  fi
  OUT=$(cd "$GG_HOME" && echo "INFO ALL" | ./ggsci 2>&1); SRC="$GG_HOME/ggsci"
fi

echo "=============================================================="
echo "GoldenGate lag check  $(hostname)  $(date '+%d-%b-%Y %H:%M')"
echo "Source: $SRC   Warn at lag > ${LAG_WARN_MIN} min, checkpoint age > ${CHKPT_WARN_MIN} min"
echo "=============================================================="

echo "$OUT" | awk -v lagw="$LAG_WARN_MIN" -v ckw="$CHKPT_WARN_MIN" '
  function mins(t,  a) { split(t, a, ":"); return a[1] * 60 + a[2] + a[3] / 60 }
  BEGIN { rc = 0; printf "%-10s %-9s %-10s %10s %12s  %s\n", "Program", "Status", "Group", "Lag", "Since chkpt", "Verdict"
          printf "%-10s %-9s %-10s %10s %12s  %s\n", "-------", "------", "-----", "---", "-----------", "-------" }
  $1 ~ /^(MANAGER|EXTRACT|REPLICAT|JAGENT|PMSRVR)$/ {
    prog = $1; st = $2; grp = (NF >= 3 && $3 !~ /:/) ? $3 : "-"
    lag = ""; ck = ""
    for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+:[0-9][0-9]:[0-9][0-9]$/) { if (lag == "") lag = $i; else ck = $i }
    v = "OK"
    if (st == "ABENDED" || st == "STOPPED") { v = "CRITICAL - " st; rc = 2 }
    else if (st != "RUNNING") { v = "CHECK - " st; if (rc < 1) rc = 1 }
    else if (lag != "" && mins(lag) > lagw) { v = "WARN - lag"; if (rc < 1) rc = 1 }
    else if (ck  != "" && mins(ck)  > ckw)  { v = "WARN - checkpoint age"; if (rc < 1) rc = 1 }
    printf "%-10s %-9s %-10s %10s %12s  %s\n", prog, st, grp, (lag == "" ? "-" : lag), (ck == "" ? "-" : ck), v
    n++
  }
  END { if (n == 0) { print "No GoldenGate processes found in the output."; rc = 2 }
        print ""; print "RESULT=" rc; exit rc }'
RC=$?

echo
echo "ABENDED: look at the report (VIEW REPORT <group>) and ha/goldengate/ggserr_log_scan.ksh."
echo "Lag growing with a RUNNING Extract: check archive log reading and ha/goldengate/gg_integrated_health.sql."
echo "Time since checkpoint growing while lag is low: the process may be hung; check with SEND <group>, STATUS."
exit $RC
