-- =============================================================
-- Script   : session_summary.sql
-- Purpose  : Who is connected: sessions by user, machine and program,
--            active vs inactive, long-idle sessions, and current use of
--            the PROCESSES and SESSIONS limits
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT to see every PDB (Container column), or a PDB
--            to see only that PDB. RAC: all instances (GV$).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @session_summary.sql
-- Settings : "idle_hours" = list INACTIVE sessions idle at least this long.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE idle_hours = 8
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET session_summary_saved_settings.sql REPLACE
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
TTITLE LEFT 'Session summary   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN resource_name FORMAT a12 HEADING 'Resource'
COLUMN inst          FORMAT 990 HEADING 'Inst'
COLUMN now           FORMAT 999,990 HEADING 'Now'
COLUMN peak          FORMAT 999,990 HEADING 'Peak'
COLUMN lim           FORMAT a8 HEADING 'Limit'
PROMPT
PROMPT Processes and sessions against their limits, per instance
SELECT inst_id AS inst, resource_name, current_utilization AS now, max_utilization AS peak, TRIM(limit_value) AS lim
FROM   gv$resource_limit
WHERE  resource_name IN ('processes', 'sessions')
ORDER  BY inst_id, resource_name;

COLUMN con      FORMAT a14     HEADING 'Container'
COLUMN username FORMAT a24     HEADING 'User'
COLUMN total    FORMAT 99,990  HEADING 'Sessions'
COLUMN active   FORMAT 99,990  HEADING 'Active'
COLUMN inactive FORMAT 99,990  HEADING 'Inactive'
BREAK ON REPORT
COMPUTE SUM LABEL 'Total' OF total active inactive ON REPORT
PROMPT
PROMPT User sessions by container and user
SELECT (SELECT c.name FROM v$containers c WHERE c.con_id = s.con_id) AS con,
       s.username,
       COUNT(*) AS total,
       SUM(CASE WHEN s.status = 'ACTIVE' THEN 1 ELSE 0 END)   AS active,
       SUM(CASE WHEN s.status = 'INACTIVE' THEN 1 ELSE 0 END) AS inactive
FROM   gv$session s
WHERE  s.type = 'USER'
GROUP  BY s.con_id, s.username
ORDER  BY total DESC
FETCH FIRST 40 ROWS ONLY;
CLEAR BREAKS
CLEAR COMPUTES

COLUMN machine FORMAT a34 HEADING 'Machine'
COLUMN program FORMAT a40 HEADING 'Program'
PROMPT
PROMPT Sessions by machine and program
SELECT machine, program, COUNT(*) AS total
FROM   gv$session
WHERE  type = 'USER'
GROUP  BY machine, program
ORDER  BY total DESC
FETCH FIRST 25 ROWS ONLY;

COLUMN sess      FORMAT a18 HEADING 'Inst:SID,SERIAL#'
COLUMN idle_hrs  FORMAT 9,990.0 HEADING 'Idle hours'
COLUMN logon     FORMAT a15 HEADING 'Logon'
PROMPT
PROMPT INACTIVE sessions idle more than &idle_hours hours (often leaked connections)
SELECT s.inst_id || ':' || s.sid || ',' || s.serial# AS sess, s.username, s.machine,
       SUBSTR(s.program, 1, 40) AS program,
       ROUND(s.last_call_et / 3600, 1) AS idle_hrs,
       TO_CHAR(s.logon_time, 'DD-MON-YY HH24:MI') AS logon
FROM   gv$session s
WHERE  s.type = 'USER' AND s.status = 'INACTIVE' AND s.last_call_et > &idle_hours * 3600
ORDER  BY s.last_call_et DESC
FETCH FIRST 40 ROWS ONLY;

PROMPT
PROMPT Many idle sessions from one machine = check the application connection pool settings.
PROMPT Profile limits such as IDLE_TIME and SESSIONS_PER_USER: general/profile_limits.sql
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con idle_hours
SET TERMOUT OFF
@session_summary_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f session_summary_saved_settings.sql
