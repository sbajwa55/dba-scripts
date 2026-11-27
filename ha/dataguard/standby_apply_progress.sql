-- =============================================================
-- Script   : standby_apply_progress.sql
-- Purpose  : On the standby: how fast redo is being applied, transport and
--            apply lag with their recent history, last received vs last
--            applied log per thread, and the MRP/RFS processes
-- Section  : High Availability / Data Guard
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PHYSICAL STANDBY, CDB$ROOT. RAC standby: the instance
--            running MRP0 (apply runs on one instance).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @standby_apply_progress.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET standby_apply_progress_saved_settings.sql REPLACE
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
TTITLE LEFT 'Standby apply progress   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN item  FORMAT a28 HEADING 'Recovery item'
COLUMN sofar FORMAT a24 HEADING 'Value'
COLUMN units FORMAT a10 HEADING 'Units'
COLUMN ts    FORMAT a17 HEADING 'At'
PROMPT
PROMPT Media recovery progress (current apply session)
SELECT item,
       CASE WHEN item = 'Last Applied Redo' THEN comments ELSE TO_CHAR(sofar) END AS sofar,
       units,
       TO_CHAR(timestamp, 'DD-MON-YY HH24:MI:SS') AS ts
FROM   v$recovery_progress
WHERE  start_time = (SELECT MAX(start_time) FROM v$recovery_progress)
AND    item IN ('Active Apply Rate', 'Average Apply Rate', 'Maximum Apply Rate', 'Redo Applied',
                'Last Applied Redo', 'Active Time', 'Apply Time per Log', 'Elapsed Time');

COLUMN name  FORMAT a24 HEADING 'Statistic'
COLUMN value FORMAT a20 HEADING 'Value'
COLUMN computed FORMAT a20 HEADING 'Computed'
PROMPT
SELECT name, value, time_computed AS computed
FROM   v$dataguard_stats
WHERE  name IN ('transport lag', 'apply lag', 'apply finish time', 'estimated startup time');

COLUMN lag_bucket FORMAT a14     HEADING 'Apply lag'
COLUMN count      FORMAT 999,999,990 HEADING 'Times seen'
COLUMN last_seen  FORMAT a20     HEADING 'Last seen'
PROMPT
PROMPT Apply lag history (how often the lag was at each level since startup)
SELECT TO_CHAR(time) || ' ' || unit AS lag_bucket, count, last_time_updated AS last_seen
FROM   v$standby_event_histogram
WHERE  name = 'apply lag' AND count > 0
ORDER  BY CASE unit WHEN 'seconds' THEN 1 WHEN 'minutes' THEN 60 WHEN 'hours' THEN 3600 ELSE 86400 END * time;

COLUMN thread#   FORMAT 990     HEADING 'Thread'
COLUMN received  FORMAT 9999990 HEADING 'Last received'
COLUMN applied   FORMAT 9999990 HEADING 'Last applied'
COLUMN behind    FORMAT 99990   HEADING 'Logs behind'
PROMPT
PROMPT Last received vs last applied log sequence per thread
SELECT thread#,
       MAX(sequence#) AS received,
       MAX(CASE WHEN applied = 'YES' THEN sequence# END) AS applied,
       MAX(sequence#) - MAX(CASE WHEN applied = 'YES' THEN sequence# END) AS behind
FROM   v$archived_log
WHERE  resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
GROUP  BY thread#
ORDER  BY thread#;

COLUMN pname    FORMAT a8  HEADING 'Process'
COLUMN action   FORMAT a14 HEADING 'Action'
COLUMN client   FORMAT a12 HEADING 'Client'
COLUMN seq      FORMAT 9999990 HEADING 'Sequence'
COLUMN block    FORMAT 999,999,990 HEADING 'Block'
PROMPT
PROMPT Apply (MRP/PR) and receive (RFS) processes
SELECT name AS pname, action, client_role AS client, thread#, sequence# AS seq, block#  AS block
FROM   v$dataguard_process
WHERE  name LIKE 'MRP%' OR name LIKE 'PR0%' OR name LIKE 'rfs%' OR role LIKE '%RFS%'
ORDER  BY name;

PROMPT
PROMPT No MRP0 row = apply is stopped. Start it:  ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT;
PROMPT  (with the broker: DGMGRL> EDIT DATABASE <standby> SET STATE='APPLY-ON';)
PROMPT Transport lag rising = network or primary side; apply lag rising alone = standby I/O or CPU.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@standby_apply_progress_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f standby_apply_progress_saved_settings.sql
