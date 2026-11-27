-- =============================================================
-- Script   : rman_backup_progress.sql
-- Purpose  : Progress of RMAN backups and restores that are running now:
--            % done, time elapsed, estimated time left and I/O rate
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT (backups cover the whole CDB, so
--            RMAN history is held in the root). Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @rman_backup_progress.sql
-- Settings : None. Run it again to refresh, or in SQL*Plus use
--            a loop: SQL> @rman_backup_progress.sql  (repeat with /)
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET rman_backup_progress_saved_settings.sql REPLACE
SET TERMOUT ON

SET PAGESIZE 200
SET LINESIZE 200
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET TRIMOUT ON
SET TRIMSPOOL ON
SET TAB OFF
SET UNDERLINE =
SET LONG 4000

COLUMN hdr_db  NEW_VALUE v_db  NOPRINT
COLUMN hdr_con NEW_VALUE v_con NOPRINT
SELECT SYS_CONTEXT('USERENV','DB_NAME') hdr_db, SYS_CONTEXT('USERENV','CON_NAME') hdr_con FROM dual;
TTITLE LEFT 'RMAN progress   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN inst_id   FORMAT 990      HEADING 'Inst'
COLUMN sid       FORMAT 99990    HEADING 'SID'
COLUMN opname    FORMAT a34      HEADING 'Operation'
COLUMN pct_done  FORMAT 990.0    HEADING '% done'
COLUMN elapsed   FORMAT a10      HEADING 'Elapsed'
COLUMN remaining FORMAT a10      HEADING 'Left (est)'
COLUMN gb_done   FORMAT 99,990.9 HEADING 'GB done'
COLUMN gb_total  FORMAT 99,990.9 HEADING 'GB total'

PROMPT
PROMPT Overall progress of each running RMAN job (aggregate rows)
SELECT l.inst_id,
       l.sid,
       l.opname,
       ROUND(l.sofar / NULLIF(l.totalwork, 0) * 100, 1)                  AS pct_done,
       TO_CHAR(TRUNC(l.elapsed_seconds/3600),'FM00') || ':' ||
       TO_CHAR(TRUNC(MOD(l.elapsed_seconds,3600)/60),'FM00') || ':' ||
       TO_CHAR(MOD(l.elapsed_seconds,60),'FM00')                          AS elapsed,
       TO_CHAR(TRUNC(l.time_remaining/3600),'FM00') || ':' ||
       TO_CHAR(TRUNC(MOD(l.time_remaining,3600)/60),'FM00') || ':' ||
       TO_CHAR(MOD(l.time_remaining,60),'FM00')                           AS remaining
FROM   gv$session_longops l
WHERE  l.opname LIKE 'RMAN%aggregate%'
AND    l.sofar < l.totalwork
ORDER  BY l.inst_id, l.sid;

PROMPT
PROMPT Individual RMAN channels still working
SELECT l.inst_id,
       l.sid,
       l.opname,
       ROUND(l.sofar / NULLIF(l.totalwork, 0) * 100, 1)                  AS pct_done,
       ROUND(l.sofar     * p.value / POWER(1024,3), 1)                   AS gb_done,
       ROUND(l.totalwork * p.value / POWER(1024,3), 1)                   AS gb_total
FROM   gv$session_longops l
       JOIN v$parameter p ON p.name = 'db_block_size'
WHERE  l.opname LIKE 'RMAN%'
AND    l.opname NOT LIKE '%aggregate%'
AND    l.units = 'Blocks'
AND    l.sofar < l.totalwork
ORDER  BY l.inst_id, l.sid;

COLUMN client_info FORMAT a30 HEADING 'Channel'
COLUMN event       FORMAT a40 HEADING 'Waiting on'
COLUMN secs        FORMAT 99,990 HEADING 'Secs'
PROMPT
PROMPT RMAN channel sessions and what they are waiting on
SELECT s.inst_id, s.sid, s.client_info, s.event, s.seconds_in_wait AS secs
FROM   gv$session s
WHERE  s.program LIKE 'rman%'
AND    s.client_info LIKE '%rman channel%'
ORDER  BY s.inst_id, s.sid;

PROMPT
PROMPT No rows = no RMAN job is running now. Finished jobs: backups/rman_backup_status.sql
PROMPT High "sbtwrite2"/"sbtbackup" waits = waiting on the tape/media manager, not the database.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con 
SET TERMOUT OFF
@rman_backup_progress_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f rman_backup_progress_saved_settings.sql
