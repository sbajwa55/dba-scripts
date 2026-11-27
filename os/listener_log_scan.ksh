#!/bin/ksh
# =============================================================
# Script   : listener_log_scan.ksh
# Purpose  : Scan every Oracle listener log on this server for the
#            last N days: connections and failures per day, TNS-
#            errors by code, top client hosts, services and programs,
#            the latest errors, and logs that have grown too big
# Section  : OS
# Platform : Oracle Linux / RHEL (ksh or bash, GNU awk/date);
#            Oracle 19c, 21c; RAC (SCAN listeners) and Exadata
# Run as   : oracle (and grid, for listeners owned by grid)
# Where    : Each database server; it finds the listener logs under
#            the ADR base ($ORACLE_BASE/diag/tnslsnr)
# Changes  : None (read-only)
# Usage    : ./listener_log_scan.ksh [days]         default 1 (today)
#            ORACLE_BASE=/u01/app/oracle ./listener_log_scan.ksh 7
# Settings : BIG_MB below = warn when a listener log is larger.
# Notes    : Reads the text log (trace/<listener>.log). Oracle does
#            not rotate that file; see the hint at the end.
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

DAYS=${1:-1}
BIG_MB=1024
BASES="${ORACLE_BASE:-/u01/app/oracle} /u01/app/grid"

# Dates in the listener log look like 27-NOV-2026
DATES=""
i=0
while [ $i -lt $DAYS ]; do
  DATES="$DATES $(date -d "-$i days" '+%d-%b-%Y' | tr '[:lower:]' '[:upper:]')"
  i=$((i + 1))
done

echo "=============================================================="
echo "Listener log scan on $(hostname), last $DAYS day(s):$DATES"
echo "=============================================================="
echo
echo "Listeners running now:"
LSNRS=$(ps -eo user,args | awk '/tnslsn[r]/ {print "   " $1 "  " $3}' | sort -u)
echo "${LSNRS:-   (none found)}"

FOUND=0
for BASE in $BASES; do
  for LOG in $(ls $BASE/diag/tnslsnr/*/*/trace/*.log 2>/dev/null); do
    FOUND=1
    SIZE_MB=$(( $(stat -c %s "$LOG") / 1024 / 1024 ))
    echo
    echo ">> $LOG  (${SIZE_MB} MB)"
    [ $SIZE_MB -ge $BIG_MB ] && echo "   WARNING: log is over ${BIG_MB} MB - rotate it (see the end of this report)"

    awk -v dates="$DATES" '
      BEGIN { n = split(dates, d, " "); for (k = 1; k <= n; k++) want[d[k]] = 1 }
      /^[0-9][0-9]-[A-Z][A-Z][A-Z]-[0-9][0-9][0-9][0-9] / {
        day = substr($0, 1, 11); inwin = (day in want)
        if (!inwin) next
        if ($0 ~ /\* establish \*/) {
          conn[day]++
          rc = $NF
          if (rc != "0") { fail[day]++; lasterr[++e] = substr($0, 1, 20) " rc=" rc " " svcname($0) " from " hostof($0) }
          h = hostof($0); hosts[h]++
          s = svcname($0); svcs[s]++
          if (match($0, /PROGRAM=[^)]*/)) progs[substr($0, RSTART + 8, RLENGTH - 8)]++
        }
        next
      }
      inwin && /^TNS-[0-9]+/ { code = substr($0, 1, index($0, ":") - 1); tns[code]++; if (!(code in txt)) txt[code] = substr($0, 1, 90) }
      function hostof(l,   t) { t = l; sub(/.*ADDRESS=\(PROTOCOL=[a-z]+\)\(HOST=/, "", t); sub(/\).*/, "", t); return t }
      function svcname(l,  t) { if (match(l, /SERVICE_NAME=[^)]*/)) return substr(l, RSTART + 13, RLENGTH - 13)
                                if (match(l, /SID=[^)]*/)) return "SID " substr(l, RSTART + 4, RLENGTH - 4); return "?" }
      function top(arr, title, lim,   k, c, out) {
        print "   " title
        c = 0
        for (k in arr) out[++c] = sprintf("%9d  %s", arr[k], k)
        if (c == 0) { print "     (none)"; return }
        # simple sort, highest first
        for (i = 1; i <= c; i++) for (j = i + 1; j <= c; j++) if (out[j] + 0 > out[i] + 0) { t = out[i]; out[i] = out[j]; out[j] = t }
        for (i = 1; i <= c && i <= lim; i++) print "   " out[i]
      }
      END {
        print "   Connections per day:"
        none = 1
        for (k in conn) { none = 0; printf "     %s  %9d connections  %7d failed\n", k, conn[k], fail[k] + 0 }
        if (none) { print "     no connections logged in this period"; exit }
        print "   TNS- errors by code:"
        if (length(tns) == 0) print "     none"
        for (c in tns) printf "     %-10s %7d  %s\n", c, tns[c], txt[c]
        top(hosts, "Top 10 client hosts:", 10)
        top(svcs,  "Top 10 services:", 10)
        top(progs, "Top 10 programs:", 10)
        if (e > 0) {
          print "   Last 15 failed connections:"
          for (i = (e > 15 ? e - 14 : 1); i <= e; i++) print "     " lasterr[i]
        }
      }' "$LOG"
  done
done

[ $FOUND -eq 0 ] && echo "No listener logs found under $BASES/diag/tnslsnr. Set ORACLE_BASE and run again."
echo
echo "Common codes: TNS-12514 service not known (check service_names / registration),"
echo "TNS-12519/12516 no handler (PROCESSES or SESSIONS limit reached), TNS-12541 no listener,"
echo "TNS-12170/12535/12547 connection timed out or dropped (network or firewall)."
echo "Rotate a big log without stopping the listener:"
echo "   lsnrctl set log_status off; mv <log> <log>.\$(date +%Y%m%d); lsnrctl set log_status on"
echo "(for a named listener use: lsnrctl, then SET CURRENT_LISTENER <name> first)"
