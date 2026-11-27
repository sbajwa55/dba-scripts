#!/bin/ksh
# =============================================================
# Script   : rac_services_check.ksh
# Purpose  : RAC service placement from Clusterware: for every
#            database and service, the preferred and available
#            instances and where it is actually running, flagging
#            services that are down, failed over, or missing from a
#            preferred instance, with the srvctl command to fix each
# Section  : High Availability / RAC
# Platform : Oracle Linux / RHEL (ksh or bash); RAC 19c, 21c
#            (administrator-managed databases)
# Run as   : oracle, with ORACLE_HOME set to the database home
# Where    : Any one cluster node (srvctl covers the whole cluster)
# Changes  : None (read-only: srvctl config/status only). The fix
#            commands are printed, never run.
# Usage    : ./rac_services_check.ksh            all databases
#            ./rac_services_check.ksh ORCL       one database (db_unique_name)
# Exit     : 0 = every service OK, 1 = something to look at
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

PATH=$ORACLE_HOME/bin:$PATH; export PATH
command -v srvctl >/dev/null 2>&1 || { echo "srvctl not found: set ORACLE_HOME to the database home"; exit 1; }

DBS=${1:-$(srvctl config database 2>/dev/null)}
[ -z "$DBS" ] && { echo "No databases registered with Clusterware."; exit 1; }

TMPC=/tmp/rac_svc_cfg.$$; TMPS=/tmp/rac_svc_st.$$
trap 'rm -f $TMPC $TMPS' EXIT
RC=0

echo "=============================================================="
echo "RAC services check  $(hostname)  $(date '+%d-%b-%Y %H:%M')"
echo "=============================================================="

for DB in $DBS; do
  echo
  echo ">> Database $DB"
  srvctl status database -db "$DB" 2>&1 | sed 's/^/   /'
  srvctl config service -db "$DB" > $TMPC 2>&1
  srvctl status service -db "$DB" > $TMPS 2>&1
  echo
  awk -v db="$DB" '
    FNR == NR {                                   # config output
      if ($0 ~ /^Service name:/)          { s = $3; order[++n] = s; pref[s] = ""; avail[s] = "" }
      if ($0 ~ /^Preferred instances:/)   { pref[s]  = $3 }
      if ($0 ~ /^Available instances:/)   { avail[s] = $3 }
      next
    }
    /^Service .* is running on instance/ { run[$2] = $NF }
    /^Service .* is not running/         { run[$2] = "" }
    END {
      if (n == 0) { print "   No services defined (only the default service is in use)."; exit 0 }
      printf "   %-24s %-18s %-14s %-18s %s\n", "Service", "Preferred", "Available", "Running on", "Verdict"
      bad = 0
      for (i = 1; i <= n; i++) {
        s = order[i]; r = run[s]; v = "OK"; fix = ""
        np = split(pref[s], P, ","); split(r, R, ",")
        for (k in R) isrun[s, R[k]] = 1
        missing = ""
        for (k = 1; k <= np; k++) if (!((s, P[k]) in isrun)) missing = missing (missing ? "," : "") P[k]
        onavail = ""
        for (k in R) if (R[k] != "" && index("," pref[s] ",", "," R[k] ",") == 0) onavail = R[k]
        if (r == "") { v = "DOWN"; fix = "srvctl start service -db " db " -service " s }
        else if (onavail != "" && missing != "") {
          v = "FAILED OVER to " onavail
          fix = "srvctl relocate service -db " db " -service " s " -oldinst " onavail " -newinst " substr(missing, 1, index(missing "," , ",") - 1) }
        else if (missing != "") { v = "NOT ON " missing; fix = "srvctl start service -db " db " -service " s " -instance " missing }
        if (v != "OK") bad = 1
        printf "   %-24s %-18s %-14s %-18s %s\n", s, pref[s], (avail[s] == "" ? "-" : avail[s]), (r == "" ? "-" : r), v
        if (fix != "") print "      fix: " fix
      }
      exit bad
    }' $TMPC $TMPS || RC=1
done

echo
echo "FAILED OVER is normal right after a node or instance restart: relocate back in a quiet period"
echo "(relocating moves new connections; existing sessions stay unless you use -drain_timeout / -stopoption)."
echo "Database-side view of the same services: ha/rac/rac_load_balance.sql"
exit $RC
