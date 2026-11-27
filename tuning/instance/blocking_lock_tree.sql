-- =============================================================
-- Script   : blocking_lock_tree.sql
-- Purpose  : Who is blocking whom right now, shown as a tree from the
--            root blocker down, with the locked objects, the SQL and
--            the command to end the root blocker if you decide to
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see every PDB. Non-CDB: run
--            normally. RAC: covers all instances (GV$ views).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @blocking_lock_tree.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET blocking_lock_tree_saved_settings.sql REPLACE
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
TTITLE LEFT 'Blocking lock tree   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN tree     FORMAT a26 HEADING 'Inst:SID (tree)'
COLUMN username FORMAT a14 HEADING 'User'
COLUMN status   FORMAT a8  HEADING 'Status'
COLUMN event    FORMAT a34 HEADING 'Waiting on'
COLUMN secs     FORMAT 9,999,990 HEADING 'Secs'
COLUMN sql_id   FORMAT a13 HEADING 'SQL_ID'
COLUMN machine  FORMAT a22 HEADING 'Machine'
PROMPT
PROMPT Blocking tree (root blockers at the left; no rows = nobody is blocked)
WITH s AS (
  SELECT inst_id, sid, serial#, username, status, event, seconds_in_wait,
         NVL(sql_id, prev_sql_id) AS sql_id, machine, blocking_instance, blocking_session
  FROM   gv$session)
SELECT LPAD(' ', 2 * (LEVEL - 1)) || s.inst_id || ':' || s.sid AS tree,
       s.username, s.status,
       CASE WHEN LEVEL = 1 THEN '(root blocker) ' END || s.event AS event,
       s.seconds_in_wait AS secs, s.sql_id, s.machine
FROM   s
START  WITH s.blocking_session IS NULL
       AND (s.inst_id, s.sid) IN (SELECT blocking_instance, blocking_session FROM s
                                  WHERE blocking_session IS NOT NULL)
CONNECT BY PRIOR s.inst_id = s.blocking_instance AND PRIOR s.sid = s.blocking_session;

COLUMN object    FORMAT a45 HEADING 'Locked object'
COLUMN lmode     FORMAT a14 HEADING 'Lock mode'
PROMPT
PROMPT Objects locked by sessions that are blocking others
SELECT DISTINCT lo.inst_id || ':' || lo.session_id AS tree,
       o.owner || '.' || o.object_name || ' (' || o.object_type || ')' AS object,
       DECODE(lo.locked_mode, 1,'Null', 2,'Row share', 3,'Row exclusive', 4,'Share',
                              5,'Share row ex', 6,'Exclusive', TO_CHAR(lo.locked_mode)) AS lmode
FROM   gv$locked_object lo
       JOIN cdb_objects o ON o.object_id = lo.object_id AND o.con_id = lo.con_id
WHERE  (lo.inst_id, lo.session_id) IN (SELECT blocking_instance, blocking_session FROM gv$session
                                       WHERE blocking_session IS NOT NULL)
ORDER  BY 1, 2;

COLUMN kill_cmd FORMAT a70 HEADING 'Command to end a root blocker (review first!)'
PROMPT
SELECT DISTINCT 'ALTER SYSTEM KILL SESSION ' || CHR(39) || b.sid || ',' || b.serial# || ',@' || b.inst_id || CHR(39) || ' IMMEDIATE;' AS kill_cmd
FROM   gv$session b
WHERE  (b.inst_id, b.sid) IN (SELECT blocking_instance, blocking_session FROM gv$session WHERE blocking_session IS NOT NULL)
AND    b.blocking_session IS NULL;

PROMPT
PROMPT This script only prints the KILL command; it does not run it. Ending a session rolls back
PROMPT its open transaction, which can take as long as the work it undoes. Contact the user first.
PROMPT A root blocker with status INACTIVE is usually an application that did not commit.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@blocking_lock_tree_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f blocking_lock_tree_saved_settings.sql
