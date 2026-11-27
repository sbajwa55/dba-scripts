-- =============================================================
-- Script   : dg_redo_transport.sql
-- Purpose  : On the primary: how each standby destination is configured
--            (SYNC/ASYNC, AFFIRM, timeout, compression, delay), its
--            current error, the last log shipped and applied per thread,
--            and logs shipped per day
-- Section  : High Availability / Data Guard
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PRIMARY, CDB$ROOT or non-CDB.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @dg_redo_transport.sql
-- Settings : "days_back" = days of shipping history.
-- Notes    : Redo transport COMPRESSION needs the Advanced Compression
--            option licence.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 7
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET dg_redo_transport_saved_settings.sql REPLACE
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
TTITLE LEFT 'Data Guard redo transport   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN dest_id     FORMAT 990  HEADING 'Dest'
COLUMN target      FORMAT a20  HEADING 'Target (service)'
COLUMN mode_       FORMAT a12  HEADING 'Mode'
COLUMN net_timeout FORMAT 9990 HEADING 'Net timeout'
COLUMN compress    FORMAT a8   HEADING 'Compress'
COLUMN delay_mins  FORMAT 9990 HEADING 'Delay min'
COLUMN status      FORMAT a9   HEADING 'Status'
COLUMN error       FORMAT a40  HEADING 'Error' WORD_WRAPPED
PROMPT
PROMPT Standby destinations
SELECT dest_id, db_unique_name || ' (' || SUBSTR(destination, 1, 12) || ')' AS target,
       transmit_mode || DECODE(affirm, 'YES', '/AFFIRM', '') AS mode_,
       net_timeout, compression AS compress, delay_mins, status, error
FROM   v$archive_dest
WHERE  target = 'STANDBY' AND status <> 'INACTIVE'
ORDER  BY dest_id;

COLUMN thread#  FORMAT 990     HEADING 'Thread'
COLUMN current_ FORMAT 9999990 HEADING 'Current seq (primary)'
COLUMN shipped  FORMAT 9999990 HEADING 'Last shipped'
COLUMN applied  FORMAT 9999990 HEADING 'Last applied'
COLUMN applied_at FORMAT a15   HEADING 'Applied at'
PROMPT
PROMPT Per destination and thread: last shipped and last applied sequence
SELECT a.dest_id, a.thread#,
       (SELECT MAX(sequence#) FROM v$log l WHERE l.thread# = a.thread# AND l.status = 'CURRENT') AS current_,
       MAX(a.sequence#) AS shipped,
       MAX(CASE WHEN a.applied = 'YES' THEN a.sequence# END) AS applied,
       TO_CHAR(MAX(CASE WHEN a.applied = 'YES' THEN a.completion_time END), 'DD-MON HH24:MI') AS applied_at
FROM   v$archived_log a
WHERE  a.dest_id IN (SELECT dest_id FROM v$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE')
AND    a.resetlogs_change# = (SELECT resetlogs_change# FROM v$database)
GROUP  BY a.dest_id, a.thread#
ORDER  BY a.dest_id, a.thread#;

COLUMN day   FORMAT a10       HEADING 'Day'
COLUMN logs  FORMAT 999,990   HEADING 'Logs shipped'
COLUMN gb    FORMAT 99,990.0  HEADING 'GB'
PROMPT
PROMPT Logs shipped per destination per day, last &days_back days
BREAK ON dest_id SKIP 1
SELECT dest_id, TO_CHAR(first_time, 'YYYY-MM-DD') AS day, COUNT(*) AS logs,
       ROUND(SUM(blocks * block_size) / POWER(1024,3), 1) AS gb
FROM   v$archived_log
WHERE  dest_id IN (SELECT dest_id FROM v$archive_dest WHERE target = 'STANDBY' AND status <> 'INACTIVE')
AND    first_time > SYSDATE - &days_back
GROUP  BY dest_id, TO_CHAR(first_time, 'YYYY-MM-DD')
ORDER  BY dest_id, day;
CLEAR BREAKS

PROMPT
PROMPT "Last applied" well behind "Last shipped" = the standby is not applying (see standby_apply_progress.sql).
PROMPT SYNC destinations add network round-trip time to every commit; watch "log file sync" on the primary.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@dg_redo_transport_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f dg_redo_transport_saved_settings.sql
