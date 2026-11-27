#!/bin/ksh
# =============================================================
# Script   : datapump_export.ksh
# Purpose  : Consistent Data Pump export of one or more schemas
#            (or a full export) with date-stamped dump and log
#            files, a checksum file, and removal of old exports
# Section  : Backups
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c
# Run as   : oracle, connecting as a database user with the
#            DATAPUMP_EXP_FULL_DATABASE role (not SYS)
# Where    : Database server or any host with the Oracle client and
#            access to the directory path. CDB: export from the PDB
#            (use a connect string or wallet alias for the PDB).
# Changes  : YES - writes dump files to the directory and deletes
#            this script's own exports older than KEEP_DAYS
# Usage    : ./datapump_export.ksh <SCHEMAS|FULL>
#            ./datapump_export.ksh HR,SALES
#            DP_CONNECT=/@PDB1_DP ./datapump_export.ksh FULL
# Settings : DP_CONNECT  connect string. Default /@dpexport uses an
#                        Oracle wallet (secure external password
#                        store) so no password is in the script.
#            DP_DIR      Oracle DIRECTORY object  (default DP_EXPORT)
#            DP_PATH     OS path of DP_DIR, used for cleanup and
#                        checksums (default: looked up in the DB)
#            PARALLEL    worker processes          (default 2)
#            COMPRESS    ALL | METADATA_ONLY      (default METADATA_ONLY)
#                        ALL needs the Advanced Compression Option.
#            KEEP_DAYS   days of exports to keep   (default 7)
# Notes    : A Data Pump export is a logical copy, not a replacement
#            for RMAN. FLASHBACK_TIME makes the export consistent to
#            one point in time; it needs enough UNDO for the run time.
#            Create the directory once (as a DBA, in the PDB):
#              CREATE DIRECTORY DP_EXPORT AS '<BACKUP_DIR>/datapump';
#              GRANT READ, WRITE ON DIRECTORY DP_EXPORT TO <EXPORT_USER>;
#            Watch running jobs with backups/datapump_jobs_status.sql
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

WHAT=$(echo "$1" | tr 'a-z' 'A-Z')
DP_CONNECT=${DP_CONNECT:-/@dpexport}
DP_DIR=${DP_DIR:-DP_EXPORT}
PARALLEL=${PARALLEL:-2}
COMPRESS=${COMPRESS:-METADATA_ONLY}
KEEP_DAYS=${KEEP_DAYS:-7}
[ -z "$WHAT" ] && { echo "Usage: $0 <SCHEMA[,SCHEMA...]|FULL>"; exit 2; }
[ -z "$ORACLE_HOME" ] && { echo "ERROR: set ORACLE_HOME (for example with . oraenv)"; exit 2; }

# ---------- OS path of the directory object ----------------------
if [ -z "$DP_PATH" ]; then
  DP_PATH=$($ORACLE_HOME/bin/sqlplus -s "$DP_CONNECT" <<EOF | tr -d ' \r' | grep -v '^$' | tail -1
SET HEADING OFF FEEDBACK OFF PAGESIZE 0
SELECT directory_path FROM all_directories WHERE directory_name = UPPER('$DP_DIR');
EXIT
EOF
)
fi
if [ -z "$DP_PATH" ] || [ ! -d "$DP_PATH" ]; then
  echo "ERROR: cannot find the OS path of directory $DP_DIR (got '$DP_PATH'). Set DP_PATH."; exit 2
fi

STAMP=$(date '+%Y%m%d_%H%M%S')
if [ "$WHAT" = "FULL" ]; then
  NAME=full_$STAMP; SCOPE="FULL=Y"
else
  NAME=$(echo "$WHAT" | tr ',' '_' | tr 'A-Z' 'a-z')_$STAMP; SCOPE="SCHEMAS=$WHAT"
fi
PARFILE=$DP_PATH/$NAME.par

# A parameter file avoids shell quoting problems with FLASHBACK_TIME
cat > "$PARFILE" <<EOF
$SCOPE
DIRECTORY=$DP_DIR
DUMPFILE=${NAME}_%U.dmp
LOGFILE=$NAME.log
FILESIZE=10G
PARALLEL=$PARALLEL
COMPRESSION=$COMPRESS
FLASHBACK_TIME=SYSTIMESTAMP
JOB_NAME=EXP_$(echo $NAME | tr 'a-z' 'A-Z' | cut -c1-120)
METRICS=Y
LOGTIME=ALL
EOF

echo "$(date '+%F %T') Export $SCOPE to $DP_PATH ($NAME)"
$ORACLE_HOME/bin/expdp "$DP_CONNECT" PARFILE="$PARFILE"
RC=$?

# expdp returns 5 when the job completed with warnings (ORA- errors in the log)
if [ $RC -eq 0 ]; then STATUS=OK
elif [ $RC -eq 5 ]; then STATUS="COMPLETED WITH WARNINGS"
else STATUS=FAILED
fi
echo "$(date '+%F %T') Export $NAME: $STATUS (rc=$RC)"
grep -E 'ORA-[0-9]{5}' "$DP_PATH/$NAME.log" 2>/dev/null | sort | uniq -c | sort -rn | head -10

if [ "$STATUS" != "FAILED" ]; then
  ( cd "$DP_PATH" && sha256sum ${NAME}_*.dmp > $NAME.sha256 ) && \
    echo "Checksums: $DP_PATH/$NAME.sha256 (verify later with: sha256sum -c $NAME.sha256)"
  # ---------- Remove this script's exports older than KEEP_DAYS ------
  # Only names this script creates: <name>_YYYYMMDD_HHMMSS[_NN].<ext>
  TS='_[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]'
  find "$DP_PATH" -maxdepth 1 -type f \
       \( -name "*${TS}_[0-9][0-9].dmp" -o -name "*${TS}.log" \
          -o -name "*${TS}.par" -o -name "*${TS}.sha256" \) \
       -mtime +$KEEP_DAYS -print -exec rm -f {} \;
fi
exit $RC
