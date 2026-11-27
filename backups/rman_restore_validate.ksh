#!/bin/ksh
# =============================================================
# Script   : rman_restore_validate.ksh
# Purpose  : Prove that the database CAN be restored from its
#            backups, without restoring anything: RMAN reads the
#            backup pieces it would use and checks them for damage.
#            Also lists which backups a restore would need.
# Section  : Backups
# Platform : Oracle Linux / RHEL (ksh or bash); Oracle 19c, 21c;
#            single instance, RAC (run on one node) and Exadata
# Run as   : oracle (OS authentication: rman target /)
# Where    : Database server, database open or mounted.
#            CDB: checks the root and every PDB.
# Changes  : None to the database or backups (read-only). It reads
#            every backup piece, so it puts I/O load on the backup
#            storage: schedule it outside busy hours.
# Usage    : ./rman_restore_validate.ksh <ORACLE_SID> [days]
#            days = also validate archive logs needed to recover to
#            this many days ago (default 1)
# Settings : LOG_DIR log folder (default ~/rman_logs)
#            MAIL_TO e-mail on failure; empty = no mail
# Notes    : This is a strong check, but only a real restore to a
#            test server proves the whole procedure. Do one at least
#            every quarter (RMAN DUPLICATE or restore to a scratch host).
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

SID=$1
DAYS=${2:-1}
LOG_DIR=${LOG_DIR:-$HOME/rman_logs}
MAIL_TO=${MAIL_TO:-}
[ -z "$SID" ] && { echo "Usage: $0 <ORACLE_SID> [days]"; exit 2; }

export ORACLE_SID=$SID
ORAENV_ASK=NO; export ORAENV_ASK
[ -x /usr/local/bin/oraenv ] && . /usr/local/bin/oraenv >/dev/null 2>&1
if [ -z "$ORACLE_HOME" ] || [ ! -x "$ORACLE_HOME/bin/rman" ]; then
  echo "ERROR: ORACLE_HOME not set for $SID"; exit 2
fi
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'

mkdir -p "$LOG_DIR" || exit 2
LOG=$LOG_DIR/rman_${SID}_RESTORE_VALIDATE_$(date '+%Y%m%d_%H%M%S').log

echo "$(date '+%F %T') Restore validation of $SID started, log: $LOG"
$ORACLE_HOME/bin/rman target / log="$LOG" <<EOF
SET ECHO ON;
# 1. Which backups would a restore use? (no I/O on the pieces)
RESTORE DATABASE PREVIEW SUMMARY;
# 2. Read those pieces and check every block
RESTORE SPFILE VALIDATE;
RESTORE CONTROLFILE VALIDATE;
RESTORE DATABASE VALIDATE CHECK LOGICAL;
# 3. Archive logs needed to recover forward from $DAYS day(s) ago
RESTORE ARCHIVELOG FROM TIME 'SYSDATE-$DAYS' VALIDATE;
EXIT;
EOF
RC=$?

if [ $RC -ne 0 ] || grep -Eq 'RMAN-[0-9]{5}|ORA-[0-9]{5}' "$LOG"; then
  STATUS=FAILED; [ $RC -eq 0 ] && RC=1
else
  STATUS=OK
fi

echo
echo "Backups a restore would use:"
sed -n '/List of Backups/,/^$/p' "$LOG" | head -40
if grep -q 'failover to previous backup' "$LOG"; then
  echo "WARNING: RMAN had to fall back to an older backup for some files (a newer piece is missing or bad)."
fi
echo
echo "$(date '+%F %T') Restore validation of $SID: $STATUS (rc=$RC)"
if [ "$STATUS" = "FAILED" ]; then
  echo "Errors:"
  grep -E 'RMAN-[0-9]{5}|ORA-[0-9]{5}' "$LOG" | head -20
  echo "A missing or damaged piece means the database may NOT be restorable: take a new backup now."
  if [ -n "$MAIL_TO" ] && command -v mailx >/dev/null 2>&1; then
    tail -100 "$LOG" | mailx -s "RMAN restore validation FAILED: $SID on $(hostname)" "$MAIL_TO"
  fi
fi
exit $RC
