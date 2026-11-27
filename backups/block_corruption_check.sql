-- =============================================================
-- Script   : block_corruption_check.sql
-- Purpose  : Corrupt blocks found by RMAN or DBVERIFY, corruption seen
--            in backups and copies, and NOLOGGING changes since the
--            last backup (data that a restore cannot recover)
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see every container.
--            Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @block_corruption_check.sql
-- Settings : None. To refresh V$DATABASE_BLOCK_CORRUPTION, first run
--            in RMAN: BACKUP VALIDATE CHECK LOGICAL DATABASE;
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET block_corruption_check_saved_settings.sql REPLACE
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
TTITLE LEFT 'Block corruption check   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN container  FORMAT a14    HEADING 'Container'
COLUMN file#      FORMAT 9990   HEADING 'File#'
COLUMN block#     FORMAT 999999990 HEADING 'Block#'
COLUMN blocks     FORMAT 99990  HEADING 'Blocks'
COLUMN ctype      FORMAT a10    HEADING 'Type'
COLUMN segment    FORMAT a50    HEADING 'Segment (owner.name type)'

PROMPT
PROMPT Corrupt blocks recorded in the database (V$DATABASE_BLOCK_CORRUPTION)
SELECT NVL(c.name, 'NON-CDB') AS container,
       b.file#, b.block#, b.blocks, b.corruption_type AS ctype
FROM   v$database_block_corruption b
       JOIN v$datafile d ON d.file# = b.file#
       LEFT JOIN v$containers c ON c.con_id = d.con_id
ORDER  BY b.file#, b.block#;

PROMPT
PROMPT Segments that own those blocks (may take a minute on large databases)
SELECT DISTINCT e.owner || '.' || e.segment_name ||
       NVL2(e.partition_name, ':' || e.partition_name, '') || ' ' || e.segment_type AS segment,
       b.file#
FROM   v$database_block_corruption b
       JOIN cdb_extents e
         ON e.file_id = b.file#
        AND b.block# BETWEEN e.block_id AND e.block_id + e.blocks - 1
ORDER  BY 1;

PROMPT
PROMPT Corruption found inside backup sets and image copies
SELECT 'BACKUP SET' AS ctype, file#, block#, blocks FROM v$backup_corruption
UNION ALL
SELECT 'COPY',               file#, block#, blocks FROM v$copy_corruption
ORDER  BY 2, 3;

COLUMN file_name  FORMAT a55 HEADING 'Datafile'
COLUMN nolog_time FORMAT a17 HEADING 'Last NOLOGGING'
COLUMN last_bkp   FORMAT a17 HEADING 'Last backup'
PROMPT
PROMPT Datafiles with NOLOGGING changes after their last backup (restore would leave those blocks unusable)
SELECT NVL(c.name, 'NON-CDB')                              AS container,
       d.file#,
       d.name                                              AS file_name,
       TO_CHAR(d.unrecoverable_time, 'DD-MON-YY HH24:MI')  AS nolog_time,
       NVL(TO_CHAR(b.last_bkp, 'DD-MON-YY HH24:MI'), 'NEVER') AS last_bkp
FROM   v$datafile d
       LEFT JOIN (SELECT file#, MAX(completion_time) last_bkp
                  FROM   v$backup_datafile GROUP BY file#) b ON b.file# = d.file#
       LEFT JOIN v$containers c ON c.con_id = d.con_id
WHERE  d.unrecoverable_time IS NOT NULL
AND   (b.last_bkp IS NULL OR d.unrecoverable_time > b.last_bkp)
ORDER  BY d.con_id, d.file#;

COLUMN force_logging FORMAT a14 HEADING 'Force logging'
PROMPT
SELECT force_logging FROM v$database;

PROMPT
PROMPT No rows in the first three lists = no known corruption. The view only shows what the last
PROMPT RMAN VALIDATE/BACKUP found, so run BACKUP VALIDATE CHECK LOGICAL DATABASE regularly.
PROMPT Fix corrupt blocks with RMAN: RECOVER CORRUPTION LIST;  (or RECOVER DATAFILE n BLOCK m;)
PROMPT NOLOGGING rows: take a new backup of those datafiles, or turn on FORCE LOGGING (needed for Data Guard).
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con 
SET TERMOUT OFF
@block_corruption_check_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f block_corruption_check_saved_settings.sql
