-- =============================================================
-- Script   : dataguard_alerts.sql
-- Purpose  : Data Guard errors and warnings for the last N hours,
--            from V$DATAGUARD_STATUS and from the alert log
-- Section  : High Availability / Data Guard
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM or SYS (SYSDG works too)
-- Where    : Run on the primary and on each standby, in CDB$ROOT.
--            RAC: shows the instance you are connected to.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @dataguard_alerts.sql
-- Settings : "lookback_hours" below.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE lookback_hours = 24
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET dataguard_alerts_saved_settings.sql REPLACE
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
TTITLE LEFT 'Data Guard errors, last &lookback_hours hours   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN msg_time   FORMAT a17  HEADING 'Time'
COLUMN facility   FORMAT a24  HEADING 'Facility'
COLUMN severity   FORMAT a8   HEADING 'Severity'
COLUMN error_code FORMAT 99999 HEADING 'Error'
COLUMN message    FORMAT a100 HEADING 'Message' WORD_WRAPPED
PROMPT
PROMPT V$DATAGUARD_STATUS: errors and warnings
SELECT TO_CHAR(timestamp, 'DD-MON-YY HH24:MI:SS') AS msg_time,
       facility, severity, error_code, message
FROM   v$dataguard_status
WHERE  timestamp > SYSDATE - &lookback_hours / 24
AND    severity IN ('Error', 'Fatal', 'Warning')
ORDER  BY timestamp DESC;

PROMPT
PROMPT Alert log: Data Guard related lines
SELECT TO_CHAR(originating_timestamp, 'DD-MON-YY HH24:MI:SS') AS msg_time,
       TRIM(REPLACE(message_text, CHR(10), ' '))             AS message
FROM   v$diag_alert_ext
WHERE  component_id = 'rdbms'
AND    originating_timestamp > SYSTIMESTAMP - NUMTODSINTERVAL(&lookback_hours, 'HOUR')
AND   (   REGEXP_LIKE(message_text, 'ORA-16[0-9]{3}')
       OR message_text LIKE '%MRP0%terminated%'
       OR message_text LIKE '%Media Recovery Waiting%'
       OR message_text LIKE '%FAL[%'
       OR message_text LIKE '%Error 12154%'
       OR message_text LIKE '%Error 1017%'
       OR message_text LIKE '%LAD:%error%'
       OR message_text LIKE '%gap%sequence%'
       OR message_text LIKE '%Archived Log entry%failed%')
ORDER  BY originating_timestamp DESC
FETCH  FIRST 150 ROWS ONLY;
PROMPT
PROMPT Common causes: Error 1017 = password file mismatch between primary and standby;
PROMPT Error 12154/ORA-12514 = TNS or service name problem; "Media Recovery Waiting" for a long time
PROMPT on the same sequence = a gap or transport problem (check dataguard_status.sql).
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@dataguard_alerts_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f dataguard_alerts_saved_settings.sql

