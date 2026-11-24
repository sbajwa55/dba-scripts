-- =============================================================
-- Script   : gg_db_capture_apply_status.sql
-- Purpose  : Database-side view of Oracle GoldenGate: logging
--            prerequisites, integrated Extract (capture) status and
--            latency, integrated Replicat (apply) status and errors
-- Section  : High Availability / GoldenGate
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM, or the GoldenGate admin user (e.g. C##GGADMIN)
-- Where    : SOURCE database, CDB$ROOT: integrated Extract is
--            registered in the root, so capture rows appear there.
--            TARGET database, inside the target PDB: integrated
--            Replicat runs in the PDB, so apply rows appear there.
--            Sections that do not apply show "no rows".
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @gg_db_capture_apply_status.sql
-- Notes    : Classic (non-integrated) Extract/Replicat do not appear
--            in these views; check them with GGSCI / Admin Client
--            (INFO ALL, LAG) and the ggserr.log scan script.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET gg_db_capture_apply_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'GoldenGate database-side status   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN log_mode       FORMAT a12 HEADING 'Log mode'
COLUMN force_logging  FORMAT a7  HEADING 'Force'
COLUMN supp_min       FORMAT a8  HEADING 'Supp min'
COLUMN gg_param       FORMAT a12 HEADING 'GG enabled'
PROMPT
PROMPT Source prerequisites (expect ARCHIVELOG, YES, YES, TRUE)
SELECT d.log_mode, d.force_logging, d.supplemental_log_data_min AS supp_min,
       (SELECT value FROM v$parameter WHERE name = 'enable_goldengate_replication') AS gg_param
FROM   v$database d;

COLUMN capture_name FORMAT a14 HEADING 'Extract'
COLUMN cstatus      FORMAT a9  HEADING 'Status'
COLUMN state        FORMAT a40 HEADING 'Current state' TRUNCATED
COLUMN lag_sec      FORMAT 999,990 HEADING 'Lag sec'
COLUMN msgs         FORMAT 999,999,990 HEADING 'Messages'
COLUMN err          FORMAT a50 HEADING 'Last error' WORD_WRAPPED
PROMPT
PROMPT Integrated Extract (capture) on this database
SELECT c.capture_name,
       c.status                                                     AS cstatus,
       g.state,
       ROUND((SYSDATE - g.capture_message_create_time) * 86400)     AS lag_sec,
       g.total_messages_captured                                    AS msgs,
       CASE WHEN c.error_number IS NOT NULL
            THEN 'ORA-' || c.error_number || ' ' || c.error_message END AS err
FROM   dba_capture c
       LEFT JOIN v$goldengate_capture g ON g.capture_name = c.capture_name
WHERE  c.purpose LIKE '%GoldenGate%'
ORDER  BY c.capture_name;

COLUMN apply_name FORMAT a14 HEADING 'Replicat'
COLUMN astatus    FORMAT a9  HEADING 'Status'
COLUMN err_count  FORMAT 99,990 HEADING 'Errors queued'
PROMPT
PROMPT Integrated Replicat (apply) on this database / PDB
SELECT a.apply_name,
       a.status                                                     AS astatus,
       CASE WHEN a.error_number IS NOT NULL
            THEN 'ORA-' || a.error_number || ' ' || a.error_message END AS err,
       (SELECT COUNT(*) FROM dba_apply_error e WHERE e.apply_name = a.apply_name) AS err_count
FROM   dba_apply a
WHERE  a.purpose LIKE '%GoldenGate%'
ORDER  BY a.apply_name;
PROMPT
PROMPT Healthy signs: Extract STATUS = ENABLED with low lag; Replicat STATUS = ENABLED and 0 errors queued.
PROMPT Lag here is how far capture is behind the redo it is reading; check end-to-end lag with LAG in Admin Client.
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@gg_db_capture_apply_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f gg_db_capture_apply_status_saved_settings.sql

