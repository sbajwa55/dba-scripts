-- =============================================================
-- Script   : sql_plan_history.sql
-- Purpose  : Has the plan changed? AWR history of one SQL_ID: plan hash,
--            executions and time per execution for each snapshot, and a
--            summary per plan so you can see which plan is good
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The CDB root or non-CDB (AWR data is kept there).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @sql_plan_history.sql <sql_id>
-- Settings : SQL_ID is the first argument; "days_back" = history.
-- Notes    : Uses ASH/AWR views: needs the Oracle Diagnostics Pack licence
--            (Enterprise Edition). Do not run it if you are not licensed.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE sql_id = '&1'
DEFINE days_back = 14
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET sql_plan_history_saved_settings.sql REPLACE
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
TTITLE LEFT 'SQL plan history   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN plan_hash FORMAT 9999999999   HEADING 'Plan hash'
COLUMN first_seen FORMAT a15         HEADING 'First seen'
COLUMN last_seen  FORMAT a15         HEADING 'Last seen'
COLUMN execs      FORMAT 999,999,990 HEADING 'Execs'
COLUMN ela_ms     FORMAT 9,999,990.0 HEADING 'Ms/exec'
COLUMN gets       FORMAT 999,999,990 HEADING 'Gets/exec'
COLUMN rws        FORMAT 99,999,990  HEADING 'Rows/exec'
PROMPT
PROMPT Summary per plan for &sql_id, last &days_back days (lowest Ms/exec = best plan)
SELECT q.plan_hash_value AS plan_hash,
       TO_CHAR(MIN(s.end_interval_time), 'DD-MON HH24:MI') AS first_seen,
       TO_CHAR(MAX(s.end_interval_time), 'DD-MON HH24:MI') AS last_seen,
       SUM(q.executions_delta) AS execs,
       ROUND(SUM(q.elapsed_time_delta) / NULLIF(SUM(q.executions_delta), 0) / 1000, 1) AS ela_ms,
       ROUND(SUM(q.buffer_gets_delta)  / NULLIF(SUM(q.executions_delta), 0))          AS gets,
       ROUND(SUM(q.rows_processed_delta) / NULLIF(SUM(q.executions_delta), 0))        AS rws
FROM   dba_hist_sqlstat q
       JOIN dba_hist_snapshot s
         ON s.snap_id = q.snap_id AND s.dbid = q.dbid AND s.instance_number = q.instance_number
WHERE  q.sql_id = '&sql_id'
AND    s.end_interval_time > SYSDATE - &days_back
GROUP  BY q.plan_hash_value
ORDER  BY ela_ms;

COLUMN snap_end FORMAT a15 HEADING 'Snapshot end'
COLUMN inst     FORMAT 990 HEADING 'Inst'
PROMPT
PROMPT Per snapshot (newest first)
SELECT TO_CHAR(s.end_interval_time, 'DD-MON HH24:MI') AS snap_end,
       q.instance_number AS inst,
       q.plan_hash_value AS plan_hash,
       q.executions_delta AS execs,
       ROUND(q.elapsed_time_delta / NULLIF(q.executions_delta, 0) / 1000, 1) AS ela_ms,
       ROUND(q.buffer_gets_delta  / NULLIF(q.executions_delta, 0))          AS gets,
       ROUND(q.rows_processed_delta / NULLIF(q.executions_delta, 0))        AS rws
FROM   dba_hist_sqlstat q
       JOIN dba_hist_snapshot s
         ON s.snap_id = q.snap_id AND s.dbid = q.dbid AND s.instance_number = q.instance_number
WHERE  q.sql_id = '&sql_id'
AND    s.end_interval_time > SYSDATE - &days_back
ORDER  BY s.end_interval_time DESC, q.instance_number
FETCH FIRST 60 ROWS ONLY;

PROMPT
PROMPT See an older plan:  SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_WORKLOAD_REPOSITORY('&sql_id', <plan_hash>));
PROMPT Fix a good plan with SQL Plan Management (no Tuning Pack needed), for example:
PROMPT   DECLARE n PLS_INTEGER; BEGIN n := DBMS_SPM.LOAD_PLANS_FROM_AWR(begin_snap => <b>, end_snap => <e>,
PROMPT     basic_filter => 'sql_id=''&sql_id'' AND plan_hash_value=<plan_hash>'); END;
PROMPT   (or DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE if the good plan is still in memory)
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con sql_id days_back 1
SET TERMOUT OFF
@sql_plan_history_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f sql_plan_history_saved_settings.sql
