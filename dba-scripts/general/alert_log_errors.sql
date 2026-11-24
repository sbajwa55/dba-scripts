-- =============================================================
-- Script   : alert_log_errors.sql
-- Purpose  : Errors and warnings from the database alert log for
--            the last N hours, read with SQL (no OS access needed),
--            plus a count by ORA- error code
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see messages from the root and
--            every PDB (the Container column shows which).
--            RAC: shows the alert log of the instance you are
--            connected to; run it on each node.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @alert_log_errors.sql
-- Settings : "lookback_hours" below.
-- Notes    : V$DIAG_ALERT_EXT reads the XML alert log. On large logs
--            it can take a minute; keep the look-back short.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE lookback_hours = 24
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET alert_log_errors_saved_settings.sql REPLACE
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
TTITLE LEFT 'Alert log errors, last &lookback_hours hours   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN msg_time  FORMAT a17  HEADING 'Time'
COLUMN container FORMAT a14  HEADING 'Container'
COLUMN message   FORMAT a120 HEADING 'Message' WORD_WRAPPED
PROMPT
PROMPT Error and warning lines (newest first, max 200)
SELECT TO_CHAR(originating_timestamp, 'DD-MON-YY HH24:MI:SS') AS msg_time,
       NVL(container_name, '-')                              AS container,
       TRIM(REPLACE(message_text, CHR(10), ' '))             AS message
FROM   v$diag_alert_ext
WHERE  component_id = 'rdbms'
AND    originating_timestamp > SYSTIMESTAMP - NUMTODSINTERVAL(&lookback_hours, 'HOUR')
AND   (   message_text LIKE '%ORA-%'
       OR message_text LIKE '%TNS-%'
       OR message_text LIKE '%Checkpoint not complete%'
       OR message_text LIKE '%Deadlock%'
       OR message_text LIKE '%WARNING%'
       OR message_text LIKE '%terminating the instance%'
       OR message_text LIKE '%Errors in file%')
ORDER  BY originating_timestamp DESC
FETCH  FIRST 200 ROWS ONLY;

COLUMN ora_code  FORMAT a10 HEADING 'Error'
COLUMN hits      FORMAT 99,990 HEADING 'Count'
COLUMN last_seen FORMAT a17 HEADING 'Last seen'
PROMPT
PROMPT Count by ORA- error code
SELECT REGEXP_SUBSTR(message_text, 'ORA-[0-9]{5}')                 AS ora_code,
       COUNT(*)                                                    AS hits,
       TO_CHAR(MAX(originating_timestamp), 'DD-MON-YY HH24:MI')    AS last_seen
FROM   v$diag_alert_ext
WHERE  component_id = 'rdbms'
AND    originating_timestamp > SYSTIMESTAMP - NUMTODSINTERVAL(&lookback_hours, 'HOUR')
AND    REGEXP_LIKE(message_text, 'ORA-[0-9]{5}')
GROUP  BY REGEXP_SUBSTR(message_text, 'ORA-[0-9]{5}')
ORDER  BY hits DESC;
PROMPT
PROMPT Common ones: ORA-00600/07445 internal error (open an SR), ORA-01555 snapshot too old,
PROMPT ORA-01652/01653 out of space, ORA-00060 deadlock, ORA-03136/TNS-12170 client timeouts (often noise).
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@alert_log_errors_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f alert_log_errors_saved_settings.sql

