#!/bin/bash
# =============================================================
# Script   : pg_backup.sh
# Purpose  : PostgreSQL logical backup of one or all databases with
#            pg_dump (custom format), plus roles and tablespaces with
#            pg_dumpall --globals-only, a readability check of every
#            dump, checksums and removal of old backups
# Section  : Backups
# Platform : Linux (bash); PostgreSQL 13 to 17. Also works against
#            Amazon RDS / Aurora PostgreSQL from a client host.
# Run as   : OS user postgres, or any user with a ~/.pgpass entry
#            (no password in this script)
# Where    : Database server or a client host with the pg_dump that
#            matches (or is newer than) the server version
# Changes  : YES - writes backup files and deletes backup folders
#            older than KEEP_DAYS
# Usage    : ./pg_backup.sh [dbname]        no name = every database
#            PGHOST=mydb.xxxx.rds.amazonaws.com PGUSER=admin ./pg_backup.sh sales
# Settings : BACKUP_DIR folder for backups   (default /backup/pg)
#            KEEP_DAYS  days to keep         (default 7)
#            PGHOST, PGPORT, PGUSER  standard libpq variables
# Notes    : A logical dump restores to a point in time of the dump only.
#            For point-in-time recovery use physical backups
#            (pgBackRest, Barman) or RDS automated backups.
#            Restore example:
#              createdb sales_restore
#              pg_restore -d sales_restore -j 4 sales_YYYYMMDD_HHMMSS.dump
# Author   : Sandeep S. Bajwa · bajwaconsulting.com
# =============================================================

set -o pipefail
DB=$1
BACKUP_DIR=${BACKUP_DIR:-/backup/pg}
KEEP_DAYS=${KEEP_DAYS:-7}
STAMP=$(date '+%Y%m%d_%H%M%S')
DEST=$BACKUP_DIR/$STAMP
mkdir -p "$DEST" || exit 2
LOG=$DEST/pg_backup.log
exec > >(tee -a "$LOG") 2>&1

echo "$(date '+%F %T') PostgreSQL backup to $DEST (host ${PGHOST:-local socket})"
pg_dump --version

if [ -n "$DB" ]; then
  DBS=$DB
else
  DBS=$(psql -X -At -d postgres -c \
        "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY 1") || {
    echo "ERROR: cannot list databases"; exit 2; }
fi

FAIL=0
# Roles, passwords (hashed) and tablespaces are not in pg_dump output
if pg_dumpall --globals-only -f "$DEST/globals.sql" 2>"$DEST/globals.err"; then
  echo "OK      globals.sql"
else
  # On RDS the master user cannot read pg_authid; fall back without passwords
  if pg_dumpall --globals-only --no-role-passwords -f "$DEST/globals.sql"; then
    echo "OK      globals.sql (without role passwords)"
  else
    echo "FAILED  globals"; FAIL=1
  fi
fi

for d in $DBS; do
  F=$DEST/${d}_$STAMP.dump
  START=$(date +%s)
  if pg_dump -Fc -Z 6 -d "$d" -f "$F"; then
    # A dump that pg_restore cannot list is not a usable backup
    if pg_restore --list "$F" > /dev/null; then
      SIZE=$(du -h "$F" | cut -f1)
      echo "OK      $d  ($SIZE, $(( $(date +%s) - START ))s)"
    else
      echo "FAILED  $d  (dump file cannot be read)"; FAIL=1
    fi
  else
    echo "FAILED  $d  (pg_dump error)"; FAIL=1
  fi
done

( cd "$DEST" && sha256sum *.dump *.sql > SHA256SUMS 2>/dev/null )

if [ $FAIL -eq 0 ]; then
  # Remove old backup folders only after a fully successful run
  find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*_[0-9]*' \
       -mtime +$KEEP_DAYS -print -exec rm -rf {} \;
  echo "$(date '+%F %T') Backup OK"
else
  echo "$(date '+%F %T') Backup FINISHED WITH ERRORS: old backups were kept"
fi
exit $FAIL
