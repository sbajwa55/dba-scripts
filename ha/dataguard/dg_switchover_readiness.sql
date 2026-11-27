-- =============================================================
-- Script   : dg_switchover_readiness.sql
-- Purpose  : Pre-switchover checklist: one PASS/WARN/FAIL line per item
--            (switchover status, force logging, flashback, broker, standby
--            redo logs, transport errors and gaps, key parameters), then
--            online vs standby redo log sizes per thread
-- Section  : High Availability / Data Guard
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Run on the PRIMARY, then on the STANDBY: each must pass.
--            CDB$ROOT or non-CDB. RAC: one instance is enough.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @dg_switchover_readiness.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET dg_switchover_readiness_saved_settings.sql REPLACE
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
TTITLE LEFT 'Data Guard switchover readiness   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN check_name FORMAT a34 HEADING 'Check'
COLUMN value      FORMAT a40 HEADING 'Value'
COLUMN result     FORMAT a5  HEADING 'Result'
COLUMN advice     FORMAT a60 HEADING 'If not PASS' WORD_WRAPPED
PROMPT
WITH p AS (SELECT name, NVL(value, '(not set)') value FROM v$parameter),
     d AS (SELECT database_role, switchover_status, force_logging, flashback_on, protection_mode FROM v$database),
     orl AS (SELECT thread#, COUNT(*) n, MAX(bytes) b FROM v$log GROUP BY thread#),
     srl AS (SELECT thread#, COUNT(*) n, MAX(bytes) b FROM v$standby_log GROUP BY thread#)
SELECT 'Database role' check_name, database_role value, 'INFO' result, NULL advice FROM d
UNION ALL
SELECT 'Switchover status', switchover_status,
       CASE WHEN switchover_status IN ('TO STANDBY', 'SESSIONS ACTIVE', 'TO PRIMARY') THEN 'PASS'
            WHEN database_role = 'PHYSICAL STANDBY' AND switchover_status = 'NOT ALLOWED' THEN 'WARN'
            ELSE 'FAIL' END,
       'NOT ALLOWED on a standby is normal until the primary has switched; elsewhere check gaps and errors' FROM d
UNION ALL
SELECT 'Protection mode', protection_mode, 'INFO', NULL FROM d
UNION ALL
SELECT 'Force logging', force_logging, DECODE(force_logging, 'YES', 'PASS', 'FAIL'),
       'ALTER DATABASE FORCE LOGGING;  (NOLOGGING changes never reach the standby)' FROM d
UNION ALL
SELECT 'Flashback database', flashback_on, DECODE(flashback_on, 'YES', 'PASS', 'WARN'),
       'Recommended: lets the old primary be reinstated after a failover' FROM d
UNION ALL
SELECT 'dg_broker_start', value, DECODE(UPPER(value), 'TRUE', 'PASS', 'WARN'),
       'Broker not running: switch over with SQL, or ALTER SYSTEM SET dg_broker_start=TRUE' FROM p WHERE name = 'dg_broker_start'
UNION ALL
SELECT 'log_archive_config', value, CASE WHEN UPPER(value) LIKE '%DG_CONFIG%' THEN 'PASS' ELSE 'FAIL' END,
       'Set DG_CONFIG=(primary_uniq,standby_uniq) on both sides' FROM p WHERE name = 'log_archive_config'
UNION ALL
SELECT 'standby_file_management', value, DECODE(UPPER(value), 'AUTO', 'PASS', 'FAIL'),
       'ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH SID=''*'';' FROM p WHERE name = 'standby_file_management'
UNION ALL
SELECT 'fal_server', value, CASE WHEN value = '(not set)' THEN 'WARN' ELSE 'PASS' END,
       'Set on both sides so either can fetch missing logs after a role change' FROM p WHERE name = 'fal_server'
UNION ALL
SELECT 'remote_login_passwordfile', value, CASE WHEN UPPER(value) IN ('EXCLUSIVE', 'SHARED') THEN 'PASS' ELSE 'FAIL' END,
       'Redo transport authenticates with the password file' FROM p WHERE name = 'remote_login_passwordfile'
UNION ALL
SELECT 'db_lost_write_protect', value, CASE WHEN UPPER(value) = 'NONE' THEN 'WARN' ELSE 'PASS' END,
       'Recommended TYPICAL on primary and standby (MAA)' FROM p WHERE name = 'db_lost_write_protect'
UNION ALL
SELECT 'Standby redo logs, thread ' || o.thread#,
       NVL(s.n, 0) || ' SRL vs ' || o.n || ' online logs',
       CASE WHEN NVL(s.n, 0) >= o.n + 1 AND s.b = o.b THEN 'PASS'
            WHEN NVL(s.n, 0) >= o.n AND s.b = o.b THEN 'WARN' ELSE 'FAIL' END,
       'Need (online groups + 1) per thread, same size as online logs, on BOTH sides'
FROM   orl o LEFT JOIN srl s ON s.thread# = o.thread#
UNION ALL
SELECT 'Transport to dest ' || dest_id, status || ' / ' || NVL(gap_status, '-') ||
       NVL2(error, ' / ' || SUBSTR(error, 1, 30), ''),
       CASE WHEN status = 'VALID' AND NVL(gap_status, 'NO GAP') = 'NO GAP' AND error IS NULL THEN 'PASS' ELSE 'FAIL' END,
       'Fix transport errors and gaps first (see dataguard_alerts.sql)'
FROM   v$archive_dest_status
WHERE  type IN ('PHYSICAL', 'LOGICAL', 'SNAPSHOT', 'FAR SYNC') AND status <> 'INACTIVE'
UNION ALL
SELECT 'Archive gap', TO_CHAR(COUNT(*)) || ' gap(s)', DECODE(COUNT(*), 0, 'PASS', 'FAIL'),
       'Resolve with FAL or by copying and registering the missing logs' FROM v$archive_gap;

COLUMN thread#  FORMAT 990      HEADING 'Thread'
COLUMN kind     FORMAT a8       HEADING 'Type'
COLUMN groups   FORMAT 990      HEADING 'Groups'
COLUMN size_mb  FORMAT 999,990  HEADING 'Size MB'
PROMPT
PROMPT Online and standby redo logs per thread
SELECT thread#, 'ONLINE' AS kind, COUNT(*) AS groups, ROUND(MAX(bytes) / POWER(1024,2)) AS size_mb FROM v$log GROUP BY thread#
UNION ALL
SELECT thread#, 'STANDBY', COUNT(*), ROUND(MAX(bytes) / POWER(1024,2)) FROM v$standby_log GROUP BY thread#
ORDER  BY 1, 2;

PROMPT
PROMPT Final check before the real thing (19c):
PROMPT   SQL>  ALTER DATABASE SWITCHOVER TO <standby_unique_name> VERIFY;
PROMPT   DGMGRL> VALIDATE DATABASE <standby_unique_name>;    (or run ha/dataguard/dg_broker_check.ksh)
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@dg_switchover_readiness_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f dg_switchover_readiness_saved_settings.sql
