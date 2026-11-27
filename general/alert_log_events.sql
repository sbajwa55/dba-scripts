-- =============================================================
-- Script   : alert_log_events.sql
-- Purpose  : Important events from the alert log over the last N days:
--            startups and shutdowns, internal errors (ORA-600/7445),
--            ALTER SYSTEM/DATABASE commands, checkpoint and archiver
--            problems, plus a count of messages per day
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB. RAC: reads the alert log of the
--            instance you are connected to; run it on each node.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @alert_log_events.sql
-- Settings : "days_back" = how many days to look back.
-- Notes    : Complements general/alert_log_errors.sql (all ORA- errors,
--            last N hours). V$DIAG_ALERT_EXT can be slow on very large
--            alert logs; keep days_back small.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 7
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET alert_log_events_saved_settings.sql REPLACE
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
TTITLE LEFT 'Alert log events   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN day      FORMAT a10       HEADING 'Day'
COLUMN msgs     FORMAT 9,999,990 HEADING 'Messages'
COLUMN errs     FORMAT 999,990   HEADING 'ORA- lines'
COLUMN restarts FORMAT 990       HEADING 'Startups'
COLUMN cnc      FORMAT 9,990     HEADING 'Ckpt not complete'
PROMPT
PROMPT Alert log activity per day, last &days_back days
SELECT TO_CHAR(originating_timestamp, 'YYYY-MM-DD') AS day,
       COUNT(*) AS msgs,
       SUM(CASE WHEN message_text LIKE '%ORA-%' THEN 1 ELSE 0 END) AS errs,
       SUM(CASE WHEN message_text LIKE 'Starting ORACLE instance%' THEN 1 ELSE 0 END) AS restarts,
       SUM(CASE WHEN message_text LIKE '%Checkpoint not complete%' THEN 1 ELSE 0 END) AS cnc
FROM   v$diag_alert_ext
WHERE  originating_timestamp > SYSTIMESTAMP - NUMTODSINTERVAL(&days_back, 'DAY')
AND    component_id = 'rdbms'
GROUP  BY TO_CHAR(originating_timestamp, 'YYYY-MM-DD')
ORDER  BY day;

COLUMN ts       FORMAT a17  HEADING 'Time'
COLUMN category FORMAT a12  HEADING 'Event'
COLUMN con      FORMAT a12  HEADING 'Container'
COLUMN message  FORMAT a110 HEADING 'Message' WORD_WRAPPED
PROMPT
PROMPT Key events (newest first)
SELECT TO_CHAR(originating_timestamp, 'DD-MON-YY HH24:MI:SS') AS ts,
       CASE
         WHEN message_text LIKE 'Starting ORACLE instance%'      THEN 'STARTUP'
         WHEN message_text LIKE 'Shutting down%'
           OR message_text LIKE 'Instance shutdown complete%'     THEN 'SHUTDOWN'
         WHEN message_text LIKE '%ORA-00600%'
           OR message_text LIKE '%ORA-07445%'
           OR message_text LIKE '%ORA-04031%'                    THEN 'INTERNAL'
         WHEN UPPER(message_text) LIKE 'ALTER SYSTEM SET%'
           OR UPPER(message_text) LIKE 'ALTER SYSTEM RESET%'     THEN 'PARAMETER'
         WHEN UPPER(message_text) LIKE 'ALTER DATABASE%'
           OR UPPER(message_text) LIKE 'ALTER PLUGGABLE DATABASE%'
           OR UPPER(message_text) LIKE 'CREATE TABLESPACE%'
           OR UPPER(message_text) LIKE 'DROP TABLESPACE%'        THEN 'STRUCTURE'
         WHEN message_text LIKE '%Checkpoint not complete%'
           OR message_text LIKE '%ARC%: Error%'
           OR message_text LIKE '%archiver%stuck%'               THEN 'REDO/ARCH'
         WHEN message_text LIKE '%Deadlock detected%'            THEN 'DEADLOCK'
         WHEN message_text LIKE '%terminating the instance%'
           OR message_text LIKE 'Instance terminated%'           THEN 'CRASH'
       END AS category,
       NVL(con_id || '', '-') AS con,
       SUBSTR(REPLACE(message_text, CHR(10), ' '), 1, 220) AS message
FROM   v$diag_alert_ext
WHERE  originating_timestamp > SYSTIMESTAMP - NUMTODSINTERVAL(&days_back, 'DAY')
AND    component_id = 'rdbms'
AND   (message_text LIKE 'Starting ORACLE instance%' OR message_text LIKE 'Shutting down%'
    OR message_text LIKE 'Instance shutdown complete%'
    OR message_text LIKE '%ORA-00600%' OR message_text LIKE '%ORA-07445%' OR message_text LIKE '%ORA-04031%'
    OR UPPER(message_text) LIKE 'ALTER SYSTEM SET%' OR UPPER(message_text) LIKE 'ALTER SYSTEM RESET%'
    OR UPPER(message_text) LIKE 'ALTER DATABASE%' OR UPPER(message_text) LIKE 'ALTER PLUGGABLE DATABASE%'
    OR UPPER(message_text) LIKE 'CREATE TABLESPACE%' OR UPPER(message_text) LIKE 'DROP TABLESPACE%'
    OR message_text LIKE '%Checkpoint not complete%' OR message_text LIKE '%ARC%: Error%'
    OR message_text LIKE '%archiver%stuck%' OR message_text LIKE '%Deadlock detected%'
    OR message_text LIKE '%terminating the instance%' OR message_text LIKE 'Instance terminated%')
ORDER  BY originating_timestamp DESC
FETCH FIRST 150 ROWS ONLY;

COLUMN problem_key FORMAT a50 HEADING 'Problem (ADR incident)'
COLUMN last_inc    FORMAT a17 HEADING 'Last incident'
COLUMN incidents   FORMAT 9,990 HEADING 'Incidents'
PROMPT
PROMPT ADR problems (internal errors that created incidents) in the last &days_back days
SELECT problem_key, TO_CHAR(lastinc_time, 'DD-MON-YY HH24:MI') AS last_inc
FROM   v$diag_problem
WHERE  lastinc_time > SYSTIMESTAMP - NUMTODSINTERVAL(&days_back, 'DAY')
ORDER  BY lastinc_time DESC;

PROMPT
PROMPT Package an incident for Oracle Support:  adrci> ips pack problem <problem_id> in /tmp
PROMPT Same check from the OS for all databases on a server: os/alert_log_scan.ksh
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@alert_log_events_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f alert_log_events_saved_settings.sql
