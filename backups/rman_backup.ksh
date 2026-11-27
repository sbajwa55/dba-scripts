#!/bin/ksh
# =============================================================
# Script   : rman_backup.ksh
# Purpose  : Run an RMAN backup (level 0, level 1 or archive logs)
#            with compression, control file and spfile backup,
#            crosscheck and delete of obsolete backups, a log file
#            and a non-zero exit code on failure (for cron or a
#            scheduler)
# Section  : Backups
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c;
#            single instance, RAC (run on one node) and Exadata
# Run as   : oracle (OS authentication: rman target /)
# Where    : Database server. CDB: backs up the root and all PDBs.
# Changes  : YES - creates backups and, unless NO_DELETE=1, deletes
#            backups that the RMAN retention policy marks OBSOLETE
#            and archive logs that are already backed up twice
# Usage    : ./rman_backup.ksh <ORACLE_SID> <L0|L1|ARCH>
#            e.g. ./rman_backup.ksh ORCLCDB L0
#            cron: 0 1 * * 0  /home/oracle/scripts/rman_backup.ksh ORCLCDB L0
#                  0 1 * * 1-6 /home/oracle/scripts/rman_backup.ksh ORCLCDB L1
#                  0 */2 * * * /home/oracle/scripts/rman_backup.ksh ORCLCDB ARCH
# Settings : PARALLEL   channels                  (default 4)
#            BACKUP_DEST disk location; empty = Fast Recovery Area
#            LOG_DIR    log folder                (default ~/rman_logs)
#            KEEP_LOGS  days to keep log files    (default 30)
#            MAIL_TO    e-mail on failure; empty = no mail
#            NO_DELETE  1 = skip crosscheck/delete steps
# Notes    : Set the retention policy once in RMAN first, e.g.
#            CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;
#            COMPRESSION: BASIC needs no extra licence; LOW, MEDIUM and
#            HIGH need the Advanced Compression Option.
#            Check results with backups/rman_backup_status.sql
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

SID=$1
TYPE=$(echo "$2" | tr 'a-z' 'A-Z')
PARALLEL=${PARALLEL:-4}
BACKUP_DEST=${BACKUP_DEST:-}
LOG_DIR=${LOG_DIR:-$HOME/rman_logs}
KEEP_LOGS=${KEEP_LOGS:-30}
MAIL_TO=${MAIL_TO:-}
NO_DELETE=${NO_DELETE:-0}

usage() { echo "Usage: $0 <ORACLE_SID> <L0|L1|ARCH>"; exit 2; }
[ -z "$SID" ] && usage
case "$TYPE" in L0|L1|ARCH) ;; *) usage ;; esac

# ---------- Oracle environment from /etc/oratab -----------------
export ORACLE_SID=$SID
ORAENV_ASK=NO; export ORAENV_ASK
if [ -x /usr/local/bin/oraenv ]; then
  . /usr/local/bin/oraenv >/dev/null 2>&1
fi
if [ -z "$ORACLE_HOME" ] || [ ! -x "$ORACLE_HOME/bin/rman" ]; then
  echo "ERROR: ORACLE_HOME not set for $SID (check /etc/oratab or export ORACLE_HOME)"; exit 2
fi
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'

mkdir -p "$LOG_DIR" || exit 2
STAMP=$(date '+%Y%m%d_%H%M%S')
LOG=$LOG_DIR/rman_${SID}_${TYPE}_${STAMP}.log
TAG=${TYPE}_$(date '+%Y%m%d')

# ---------- Do not start a second backup of the same database ---
LOCK=/tmp/rman_backup_${SID}.lock
if [ -f "$LOCK" ] && kill -0 "$(cat $LOCK)" 2>/dev/null; then
  echo "Another rman_backup.ksh for $SID is running (PID $(cat $LOCK)). Exiting."; exit 3
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# ---------- Channels ---------------------------------------------
CHANNELS=""
i=1
while [ $i -le $PARALLEL ]; do
  if [ -n "$BACKUP_DEST" ]; then
    CHANNELS="$CHANNELS
  ALLOCATE CHANNEL d$i DEVICE TYPE DISK FORMAT '$BACKUP_DEST/%d_%T_%U';"
  else
    CHANNELS="$CHANNELS
  ALLOCATE CHANNEL d$i DEVICE TYPE DISK;"
  fi
  i=$((i + 1))
done

# ---------- What to back up --------------------------------------
case "$TYPE" in
  L0)   WORK="BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL 0 DATABASE TAG '$TAG' PLUS ARCHIVELOG NOT BACKED UP 1 TIMES TAG '${TAG}_ARC';" ;;
  L1)   WORK="BACKUP AS COMPRESSED BACKUPSET INCREMENTAL LEVEL 1 DATABASE TAG '$TAG' PLUS ARCHIVELOG NOT BACKED UP 1 TIMES TAG '${TAG}_ARC';" ;;
  ARCH) WORK="SQL 'ALTER SYSTEM ARCHIVE LOG CURRENT';
  BACKUP AS COMPRESSED BACKUPSET ARCHIVELOG ALL NOT BACKED UP 1 TIMES TAG '$TAG';" ;;
esac

if [ "$NO_DELETE" = "1" ]; then
  CLEANUP="# cleanup skipped (NO_DELETE=1)"
else
  CLEANUP="CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT ARCHIVELOG ALL BACKED UP 2 TIMES TO DEVICE TYPE DISK COMPLETED BEFORE 'SYSDATE-1';"
fi

echo "$(date '+%F %T') Starting $TYPE backup of $SID, log: $LOG"
$ORACLE_HOME/bin/rman target / log="$LOG" <<EOF
SET ECHO ON;
SHOW RETENTION POLICY;
RUN {
$CHANNELS
  $WORK
  BACKUP CURRENT CONTROLFILE TAG '${TAG}_CTL';
  BACKUP SPFILE TAG '${TAG}_SPF';
}
$CLEANUP
LIST BACKUP SUMMARY COMPLETED AFTER 'SYSDATE-1';
EXIT;
EOF
RC=$?

# RMAN can return 0 even when a step logged an error; check the log too.
# Ignored: RMAN-08137/08138/08120 = archive log kept because a standby or
# GoldenGate still needs it (normal with Data Guard, not a failure).
ERRS=$(grep -E 'RMAN-[0-9]{5}|ORA-[0-9]{5}' "$LOG" | grep -vE 'RMAN-0813[78]|RMAN-08120')
if [ $RC -ne 0 ] || [ -n "$ERRS" ]; then
  STATUS=FAILED
  [ $RC -eq 0 ] && RC=1
else
  STATUS=OK
fi
echo "$(date '+%F %T') $TYPE backup of $SID finished: $STATUS (rc=$RC)"

if [ "$STATUS" = "FAILED" ]; then
  echo "$ERRS" | head -20
  if [ -n "$MAIL_TO" ] && command -v mailx >/dev/null 2>&1; then
    tail -100 "$LOG" | mailx -s "RMAN $TYPE backup FAILED: $SID on $(hostname)" "$MAIL_TO"
  fi
fi

# ---------- Remove old log files ---------------------------------
find "$LOG_DIR" -name "rman_${SID}_*.log" -mtime +$KEEP_LOGS -exec rm -f {} \; 2>/dev/null

exit $RC
