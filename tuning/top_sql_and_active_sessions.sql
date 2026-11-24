-- =============================================================
-- Script   : top_sql_and_active_sessions.sql
-- Purpose  : What is the database doing right now? Active sessions
--            grouped by wait event, blocking sessions, and the top
--            SQL by elapsed time in the shared pool (with Exadata
--            Smart Scan offload figures)
-- Section  : Tuning
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see every PDB (Container column).
--            RAC: active sessions and blockers cover all instances
--            (GV$); top SQL covers the instance you are on.
-- Changes  : None (read-only). No AWR or Diagnostics Pack needed.
-- Client   : SQL*Plus      Usage: SQL> @top_sql_and_active_sessions.sql
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET top_sql_and_active_sessions_saved_settings.sql REPLACE
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
TTITLE LEFT 'Top SQL and active sessions   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN inst_id    FORMAT 99  HEADING 'Inst'
COLUMN container  FORMAT a14 HEADING 'Container'
COLUMN wait_class FORMAT a14 HEADING 'Wait class'
COLUMN activity   FORMAT a40 HEADING 'On CPU / waiting for'
COLUMN sessions   FORMAT 9,990 HEADING 'Sessions'
PROMPT
PROMPT Active user sessions right now, by what they are doing
SELECT s.inst_id,
       NVL(c.name, '-')                                         AS container,
       DECODE(s.state, 'WAITING', s.wait_class, 'CPU')          AS wait_class,
       DECODE(s.state, 'WAITING', s.event, 'ON CPU')            AS activity,
       COUNT(*)                                                 AS sessions
FROM   gv$session s
       LEFT JOIN v$containers c ON c.con_id = s.con_id
WHERE  s.type = 'USER'
AND    s.status = 'ACTIVE'
AND    NOT (s.state = 'WAITING' AND s.wait_class = 'Idle')
GROUP  BY s.inst_id, c.name, DECODE(s.state, 'WAITING', s.wait_class, 'CPU'), DECODE(s.state, 'WAITING', s.event, 'ON CPU')
ORDER  BY sessions DESC;

COLUMN blocker    FORMAT a14 HEADING 'Blocker'
COLUMN waiter     FORMAT a14 HEADING 'Waiting session'
COLUMN wuser      FORMAT a14 HEADING 'Waiter user'
COLUMN event      FORMAT a30 HEADING 'Waiting on'
COLUMN wait_sec   FORMAT 99,990 HEADING 'Wait sec'
COLUMN sql_id     FORMAT a13 HEADING 'Waiter SQL'
PROMPT
PROMPT Blocked sessions (no rows = nobody is blocked)
SELECT s.blocking_instance || ':' || s.blocking_session  AS blocker,
       s.inst_id || ':' || s.sid                         AS waiter,
       s.username                                        AS wuser,
       s.event,
       s.seconds_in_wait                                 AS wait_sec,
       s.sql_id
FROM   gv$session s
WHERE  s.blocking_session IS NOT NULL
ORDER  BY s.seconds_in_wait DESC;

COLUMN execs        FORMAT 999,999,990 HEADING 'Execs'
COLUMN elapsed_s    FORMAT 9,999,990   HEADING 'Elapsed s'
COLUMN ms_per_exec  FORMAT 99,999,990.9 HEADING 'ms/exec'
COLUMN cpu_pct      FORMAT 990     HEADING 'CPU %'
COLUMN gets_exec    FORMAT 999,999,990 HEADING 'Gets/exec'
COLUMN offload_pct  FORMAT 990     HEADING 'Offload %'
COLUMN sql_text     FORMAT a50     HEADING 'SQL text' TRUNCATED
PROMPT
PROMPT Top 15 SQL by total elapsed time (since loaded in the shared pool)
SELECT q.sql_id,
       NVL(c.name, '-')                                                    AS container,
       q.executions                                                        AS execs,
       ROUND(q.elapsed_time / 1e6)                                         AS elapsed_s,
       ROUND(q.elapsed_time / NULLIF(q.executions, 0) / 1000, 1)           AS ms_per_exec,
       ROUND(100 * q.cpu_time / NULLIF(q.elapsed_time, 0))                 AS cpu_pct,
       ROUND(q.buffer_gets / NULLIF(q.executions, 0))                      AS gets_exec,
       CASE WHEN q.io_cell_offload_eligible_bytes > 0
            THEN GREATEST(0, ROUND(100 * (1 - q.io_interconnect_bytes / q.io_cell_offload_eligible_bytes))) END AS offload_pct,
       REPLACE(REPLACE(q.sql_text, CHR(10), ' '), CHR(13), ' ')            AS sql_text
FROM   v$sqlarea q
       LEFT JOIN v$containers c ON c.con_id = q.con_id
WHERE  q.executions > 0
ORDER  BY q.elapsed_time DESC
FETCH  FIRST 15 ROWS ONLY;
PROMPT
PROMPT Offload % (Exadata only): share of eligible I/O that Smart Scan filtered in the storage cells.
PROMPT Blank = not eligible for Smart Scan, or not running on Exadata.
PROMPT Next step for a SQL_ID: SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR('<sql_id>', NULL, 'ALLSTATS LAST'));
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@top_sql_and_active_sessions_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f top_sql_and_active_sessions_saved_settings.sql

