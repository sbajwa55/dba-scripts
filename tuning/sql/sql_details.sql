-- =============================================================
-- Script   : sql_details.sql
-- Purpose  : Everything about one SQL statement in the shared pool: text,
--            each child cursor and plan with per-execution figures,
--            profile/baseline/patch in use, captured bind values and
--            the execution plan
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The container where the SQL runs (or CDB$ROOT to see all).
--            RAC: cursor figures come from every instance (GV$).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @sql_details.sql <sql_id>
-- Settings : SQL_ID is the first argument.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE sql_id = '&1'
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET sql_details_saved_settings.sql REPLACE
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
TTITLE LEFT 'SQL details   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

SET LONG 20000
COLUMN sql_fulltext FORMAT a180 WORD_WRAPPED HEADING 'SQL text'
PROMPT
PROMPT SQL text for &sql_id
SELECT sql_fulltext FROM gv$sqlarea WHERE sql_id = '&sql_id' AND ROWNUM = 1;

COLUMN inst      FORMAT 990        HEADING 'Inst'
COLUMN child     FORMAT 990        HEADING 'Child'
COLUMN plan_hash FORMAT 9999999999 HEADING 'Plan hash'
COLUMN execs     FORMAT 999,999,990 HEADING 'Execs'
COLUMN ela_ms    FORMAT 9,999,990.0 HEADING 'Ms/exec'
COLUMN cpu_ms    FORMAT 9,999,990.0 HEADING 'CPU ms/exec'
COLUMN gets      FORMAT 999,999,990 HEADING 'Gets/exec'
COLUMN reads     FORMAT 99,999,990 HEADING 'Reads/exec'
COLUMN rws       FORMAT 99,999,990 HEADING 'Rows/exec'
COLUMN bind      FORMAT a5         HEADING 'B S/A'
COLUMN last_used FORMAT a14        HEADING 'Last active'
PROMPT
PROMPT Child cursors (several plan hashes = the plan changes between executions)
SELECT inst_id AS inst, child_number AS child, plan_hash_value AS plan_hash,
       executions AS execs,
       ROUND(elapsed_time   / NULLIF(executions, 0) / 1000, 1) AS ela_ms,
       ROUND(cpu_time       / NULLIF(executions, 0) / 1000, 1) AS cpu_ms,
       ROUND(buffer_gets    / NULLIF(executions, 0))           AS gets,
       ROUND(disk_reads     / NULLIF(executions, 0))           AS reads,
       ROUND(rows_processed / NULLIF(executions, 0))           AS rws,
       is_bind_sensitive || '/' || is_bind_aware                AS bind,
       TO_CHAR(last_active_time, 'DD-MON HH24:MI')             AS last_used
FROM   gv$sql
WHERE  sql_id = '&sql_id'
ORDER  BY inst_id, child_number;

COLUMN fixes FORMAT a90 HEADING 'Profile / baseline / patch in use'
PROMPT
SELECT DISTINCT 'Plan ' || plan_hash_value || ':' ||
       NVL2(sql_profile,       ' profile '  || sql_profile, '') ||
       NVL2(sql_plan_baseline, ' baseline ' || sql_plan_baseline, '') ||
       NVL2(sql_patch,         ' patch '    || sql_patch, '') AS fixes
FROM   gv$sql
WHERE  sql_id = '&sql_id'
AND    COALESCE(sql_profile, sql_plan_baseline, sql_patch) IS NOT NULL;

COLUMN name     FORMAT a14 HEADING 'Bind'
COLUMN position FORMAT 990 HEADING 'Pos'
COLUMN datatype FORMAT a16 HEADING 'Type'
COLUMN value    FORMAT a40 HEADING 'Captured value'
COLUMN captured FORMAT a17 HEADING 'Captured'
PROMPT
PROMPT Captured bind values (sampled; not every execution is captured)
SELECT DISTINCT name, position, datatype_string AS datatype,
       value_string AS value, TO_CHAR(last_captured, 'DD-MON-YY HH24:MI') AS captured
FROM   gv$sql_bind_capture
WHERE  sql_id = '&sql_id'
AND    was_captured = 'YES'
ORDER  BY position, captured DESC
FETCH FIRST 30 ROWS ONLY;

SET HEADING OFF
TTITLE OFF
COLUMN plan_table_output FORMAT a200
PROMPT
PROMPT Execution plan of each child cursor on this instance (with the bind values used to build it)
SELECT plan_table_output
FROM   TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'TYPICAL +PEEKED_BINDS +NOTE'));
SET HEADING ON

PROMPT
PROMPT For actual rows per step, run the SQL with /*+ GATHER_PLAN_STATISTICS */ and then:
PROMPT   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));
PROMPT Plan history over days: tuning/sql/sql_plan_history.sql &sql_id
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con sql_id 1
SET TERMOUT OFF
@sql_details_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f sql_details_saved_settings.sql
