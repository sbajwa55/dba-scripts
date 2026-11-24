-- =============================================================
-- Script   : dataguard_status.sql
-- Purpose  : Data Guard health: role, protection mode, switchover
--            status, transport/apply lag, destinations and gaps,
--            and the redo transport/apply processes
-- Section  : High Availability / Data Guard
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM or SYS (SYSDG works too)
-- Where    : Run on the PRIMARY to check destinations and gaps,
--            and on each STANDBY to check lag and apply.
--            CDB: run in CDB$ROOT (Data Guard works at CDB level).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @dataguard_status.sql
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET dataguard_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'Data Guard status   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN db_unique_name    FORMAT a16 HEADING 'Unique name'
COLUMN database_role     FORMAT a16 HEADING 'Role'
COLUMN open_mode         FORMAT a20 HEADING 'Open mode'
COLUMN protection_mode   FORMAT a20 HEADING 'Protection'
COLUMN switchover_status FORMAT a20 HEADING 'Switchover status'
COLUMN dataguard_broker  FORMAT a9  HEADING 'Broker'
COLUMN fs_failover_status FORMAT a22 HEADING 'Fast-start failover'
PROMPT
SELECT db_unique_name, database_role, open_mode, protection_mode,
       switchover_status, dataguard_broker, fs_failover_status
FROM   v$database;

COLUMN name         FORMAT a24 HEADING 'Metric'
COLUMN value        FORMAT a20 HEADING 'Value'
COLUMN unit         FORMAT a30 HEADING 'Unit'
COLUMN time_computed FORMAT a20 HEADING 'Computed at'
PROMPT
PROMPT Lag (meaningful on a STANDBY; empty on the primary)
SELECT name, value, unit, time_computed
FROM   v$dataguard_stats
WHERE  name IN ('transport lag', 'apply lag', 'apply finish time', 'estimated startup time');

COLUMN dest_id       FORMAT 99  HEADING 'Dest'
COLUMN dest_name     FORMAT a20 HEADING 'Name'
COLUMN destination   FORMAT a22 HEADING 'Target'
COLUMN status        FORMAT a9  HEADING 'Status'
COLUMN recovery_mode FORMAT a26 HEADING 'Recovery mode'
COLUMN gap_status    FORMAT a16 HEADING 'Gap'
COLUMN archived_seq# FORMAT 9999999 HEADING 'Arch seq'
COLUMN applied_seq#  FORMAT 9999999 HEADING 'Appl seq'
COLUMN error         FORMAT a40 HEADING 'Error' WORD_WRAPPED
PROMPT
PROMPT Redo destinations (on the PRIMARY: one line per standby)
SELECT dest_id, dest_name, destination, status, recovery_mode, gap_status,
       archived_seq#, applied_seq#, error
FROM   v$archive_dest_status
WHERE  status <> 'INACTIVE'
AND    destination IS NOT NULL
ORDER  BY dest_id;

COLUMN thread#    FORMAT 99      HEADING 'Thread'
COLUMN low_seq    FORMAT 9999999 HEADING 'Missing from'
COLUMN high_seq   FORMAT 9999999 HEADING 'Missing to'
PROMPT
PROMPT Archive log gaps (on a STANDBY; no rows = no gap)
SELECT thread#, low_sequence# AS low_seq, high_sequence# AS high_seq FROM v$archive_gap;

COLUMN pname    FORMAT a8  HEADING 'Process'
COLUMN prole    FORMAT a24 HEADING 'Role'
COLUMN action   FORMAT a12 HEADING 'Action'
COLUMN client_role FORMAT a16 HEADING 'Client'
COLUMN sequence# FORMAT 9999999 HEADING 'Sequence'
PROMPT
PROMPT Data Guard processes (look for MRP0 "APPLYING_LOG" on the standby)
SELECT name AS pname, role AS prole, action, client_role, thread#, sequence#
FROM   v$dataguard_process
ORDER  BY name;
PROMPT
PROMPT Healthy signs: primary dest STATUS = VALID and GAP = NO GAP; standby transport and apply lag
PROMPT close to +00 00:00:00; MRP0 present with ACTION = APPLYING_LOG (or WAIT_FOR_LOG).
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@dataguard_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f dataguard_status_saved_settings.sql

