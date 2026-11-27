-- =============================================================
-- Script   : gg_integrated_health.sql
-- Purpose  : Integrated Extract/Replicat internals: Streams pool size and
--            use, the oldest archive log each Extract still needs (and
--            whether it is still on disk), and Replicat errors in detail
-- Section  : High Availability / GoldenGate
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Extract side: the CDB$ROOT (capture runs there). Replicat
--            side: the target PDB. Each part shows "no rows" where it
--            does not apply.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @gg_integrated_health.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET gg_integrated_health_saved_settings.sql REPLACE
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
TTITLE LEFT 'GoldenGate integrated health   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN name  FORMAT a32 HEADING 'Streams pool'
COLUMN mb    FORMAT 999,990 HEADING 'MB'
PROMPT
PROMPT Streams pool: configured size and current memory (each integrated Extract wants ~1 GB, MAX_SGA_SIZE)
SELECT 'streams_pool_size parameter' AS name, ROUND(TO_NUMBER(value) / POWER(1024,2)) AS mb
FROM   v$parameter WHERE name = 'streams_pool_size'
UNION ALL
SELECT 'Current streams pool (SGA)', ROUND(current_size / POWER(1024,2))
FROM   v$sga_dynamic_components WHERE component = 'streams pool';

COLUMN capture_name   FORMAT a20 HEADING 'Extract (capture)'
COLUMN status         FORMAT a9  HEADING 'Status'
COLUMN req_scn        FORMAT 999999999999999 HEADING 'Required SCN'
COLUMN seq            FORMAT a22 HEADING 'Oldest log needed'
COLUMN on_disk        FORMAT a8  HEADING 'On disk'
COLUMN first_time     FORMAT a15 HEADING 'Log time'
PROMPT
PROMPT Oldest archived log each Extract still needs (do NOT delete it or anything newer)
SELECT c.capture_name, c.status, c.required_checkpoint_scn AS req_scn,
       'thread ' || l.thread# || ' seq ' || l.sequence# AS seq,
       TO_CHAR(l.first_time, 'DD-MON HH24:MI') AS first_time,
       CASE WHEN EXISTS (SELECT 1 FROM v$archived_log x
                         WHERE x.thread# = l.thread# AND x.sequence# = l.sequence#
                         AND   x.deleted = 'NO' AND x.status = 'A') THEN 'YES' ELSE 'NO!' END AS on_disk
FROM   dba_capture c
       LEFT JOIN (SELECT DISTINCT thread#, sequence#, first_change#, next_change#, first_time
                  FROM v$archived_log WHERE resetlogs_change# = (SELECT resetlogs_change# FROM v$database)) l
         ON c.required_checkpoint_scn >= l.first_change# AND c.required_checkpoint_scn < l.next_change#
ORDER  BY c.capture_name, l.thread#;

COLUMN apply_name   FORMAT a20 HEADING 'Replicat (apply)'
COLUMN errs         FORMAT 99,990 HEADING 'Errors'
COLUMN msgs         FORMAT 9,999,990 HEADING 'Messages'
COLUMN error_number FORMAT 999990 HEADING 'ORA-'
COLUMN error_msg    FORMAT a70 HEADING 'Error' WORD_WRAPPED
COLUMN err_time     FORMAT a15 HEADING 'When'
PROMPT
PROMPT Replicat (apply) error queue - newest first
SELECT apply_name, TO_CHAR(error_creation_time, 'DD-MON HH24:MI') AS err_time,
       error_number, message_count AS msgs, SUBSTR(error_message, 1, 200) AS error_msg
FROM   dba_apply_error
ORDER  BY error_creation_time DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT
PROMPT RMAN: protect logs Extract needs with
PROMPT   CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;   -- or SHIPPED/BACKED UP, plus Extract registration
PROMPT   (integrated Extract registers with RMAN, so RMAN will not delete logs it still needs)
PROMPT A missing log (On disk = NO!) must be restored from backup before Extract can continue.
PROMPT Replicat errors are usually handled by REPERROR in the Replicat parameter file, not in the database.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@gg_integrated_health_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f gg_integrated_health_saved_settings.sql
