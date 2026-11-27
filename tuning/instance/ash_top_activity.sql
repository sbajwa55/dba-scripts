-- =============================================================
-- Script   : ash_top_activity.sql
-- Purpose  : What the database spent its time on in the last N minutes
--            (Active Session History): by wait class, wait event, SQL_ID,
--            module and session
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see every PDB. Non-CDB: run
--            normally. RAC: covers all instances (GV$ views).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @ash_top_activity.sql
-- Settings : "minutes" = how far back to look (ASH in memory
--            usually covers about an hour on a busy system).
-- Notes    : Uses ASH/AWR views: needs the Oracle Diagnostics Pack licence
--            (Enterprise Edition). Do not run it if you are not licensed.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE minutes = 30
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET ash_top_activity_saved_settings.sql REPLACE
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
TTITLE LEFT 'ASH top activity   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

-- One ASH sample = one active session for about one second,
-- so sample counts are roughly "seconds of DB time".
COLUMN activity FORMAT a40     HEADING 'Wait class / event'
COLUMN samples  FORMAT 999,990 HEADING 'Samples'
COLUMN pct      FORMAT 990.0   HEADING '%'
COLUMN aas      FORMAT 990.0   HEADING 'Avg active'
PROMPT
PROMPT Activity by wait class in the last &minutes minutes (Avg active > CPU count = overloaded)
SELECT CASE session_state WHEN 'ON CPU' THEN 'CPU' ELSE wait_class END AS activity,
       COUNT(*) AS samples,
       ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 1) AS pct,
       ROUND(COUNT(*) / (&minutes * 60), 1) AS aas
FROM   gv$active_session_history
WHERE  sample_time > SYSTIMESTAMP - NUMTODSINTERVAL(&minutes, 'MINUTE')
GROUP  BY CASE session_state WHEN 'ON CPU' THEN 'CPU' ELSE wait_class END
ORDER  BY samples DESC;

PROMPT
PROMPT Top 10 wait events
SELECT CASE session_state WHEN 'ON CPU' THEN 'CPU' ELSE event END AS activity,
       COUNT(*) AS samples,
       ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 1) AS pct
FROM   gv$active_session_history
WHERE  sample_time > SYSTIMESTAMP - NUMTODSINTERVAL(&minutes, 'MINUTE')
GROUP  BY CASE session_state WHEN 'ON CPU' THEN 'CPU' ELSE event END
ORDER  BY samples DESC
FETCH FIRST 10 ROWS ONLY;

COLUMN sql_id    FORMAT a13 HEADING 'SQL_ID'
COLUMN top_event FORMAT a32 HEADING 'Mostly'
COLUMN sql_text  FORMAT a50 HEADING 'SQL text' TRUNCATED
PROMPT
PROMPT Top 10 SQL_IDs (look at these with tuning/sql/sql_details.sql)
SELECT a.sql_id, a.samples, a.pct, a.top_event,
       (SELECT SUBSTR(MAX(q.sql_text), 1, 50) FROM gv$sql q WHERE q.sql_id = a.sql_id) AS sql_text
FROM  (SELECT sql_id, COUNT(*) samples,
              ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 1) pct,
              STATS_MODE(CASE session_state WHEN 'ON CPU' THEN 'CPU' ELSE event END) top_event
       FROM   gv$active_session_history
       WHERE  sample_time > SYSTIMESTAMP - NUMTODSINTERVAL(&minutes, 'MINUTE')
       AND    sql_id IS NOT NULL
       GROUP  BY sql_id) a
ORDER  BY a.samples DESC
FETCH FIRST 10 ROWS ONLY;

COLUMN module FORMAT a40 HEADING 'Module / program'
PROMPT
PROMPT Top 10 modules or programs
SELECT NVL(module, program) AS module, COUNT(*) AS samples,
       ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 1) AS pct
FROM   gv$active_session_history
WHERE  sample_time > SYSTIMESTAMP - NUMTODSINTERVAL(&minutes, 'MINUTE')
GROUP  BY NVL(module, program)
ORDER  BY samples DESC
FETCH FIRST 10 ROWS ONLY;

COLUMN sess FORMAT a14 HEADING 'Inst:SID'
COLUMN username FORMAT a16 HEADING 'User'
PROMPT
PROMPT Top 10 sessions
SELECT a.sess,
       (SELECT u.username FROM cdb_users u WHERE u.user_id = a.user_id AND u.con_id = a.con_id) AS username,
       a.samples, a.pct
FROM  (SELECT h.inst_id || ':' || h.session_id AS sess,
              MAX(h.user_id) AS user_id, MAX(h.con_id) AS con_id,
              COUNT(*) AS samples,
              ROUND(RATIO_TO_REPORT(COUNT(*)) OVER () * 100, 1) AS pct
       FROM   gv$active_session_history h
       WHERE  h.sample_time > SYSTIMESTAMP - NUMTODSINTERVAL(&minutes, 'MINUTE')
       GROUP  BY h.inst_id, h.session_id) a
ORDER  BY a.samples DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT
PROMPT For older periods use DBA_HIST_ACTIVE_SESS_HISTORY (1 sample every 10 seconds) or an ASH report:
PROMPT   SQL> @?/rdbms/admin/ashrpt.sql
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con minutes
SET TERMOUT OFF
@ash_top_activity_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f ash_top_activity_saved_settings.sql
