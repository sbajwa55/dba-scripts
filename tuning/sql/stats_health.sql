-- =============================================================
-- Script   : stats_health.sql
-- Purpose  : Optimizer statistics health for one schema: tables and
--            indexes with stale, missing or locked statistics, rows
--            changed since the last gather, and the automatic stats job
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB (or non-CDB) that holds the schema.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @stats_health.sql <SCHEMA>
-- Settings : Schema name is the first argument.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE schema = '&1'
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET stats_health_saved_settings.sql REPLACE
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
TTITLE LEFT 'Statistics health   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN table_name  FORMAT a32         HEADING 'Table'
COLUMN partition   FORMAT a20         HEADING 'Partition'
COLUMN num_rows    FORMAT 999,999,999,990 HEADING 'Rows (stats)'
COLUMN analyzed    FORMAT a15         HEADING 'Last analyzed'
COLUMN problem     FORMAT a16         HEADING 'Problem'
COLUMN changed_pct FORMAT 9,990.0     HEADING 'Changed %'
PROMPT
PROMPT Tables with stale, missing or locked statistics in schema &schema
SELECT s.table_name,
       s.partition_name AS partition,
       s.num_rows,
       NVL(TO_CHAR(s.last_analyzed, 'DD-MON-YY HH24:MI'), 'NEVER') AS analyzed,
       CASE WHEN s.last_analyzed IS NULL   THEN 'MISSING'
            WHEN s.stale_stats = 'YES'     THEN 'STALE'
            WHEN s.stattype_locked IS NOT NULL THEN 'LOCKED (' || s.stattype_locked || ')' END AS problem,
       ROUND((m.inserts + m.updates + m.deletes) / NULLIF(s.num_rows, 0) * 100, 1) AS changed_pct
FROM   dba_tab_statistics s
       LEFT JOIN dba_tab_modifications m
         ON m.table_owner = s.owner AND m.table_name = s.table_name
        AND NVL(m.partition_name, '-') = NVL(s.partition_name, '-')
        AND m.subpartition_name IS NULL
WHERE  s.owner = UPPER('&schema')
AND    s.object_type IN ('TABLE', 'PARTITION')
AND    s.table_name NOT LIKE 'BIN$%'
AND   (s.last_analyzed IS NULL OR s.stale_stats = 'YES' OR s.stattype_locked IS NOT NULL)
ORDER  BY problem, s.table_name, s.partition_name
FETCH FIRST 100 ROWS ONLY;

COLUMN index_name FORMAT a32 HEADING 'Index'
PROMPT
PROMPT Indexes with missing or stale statistics
SELECT index_name, table_name,
       NVL(TO_CHAR(last_analyzed, 'DD-MON-YY HH24:MI'), 'NEVER') AS analyzed,
       CASE WHEN last_analyzed IS NULL THEN 'MISSING' ELSE 'STALE' END AS problem
FROM   dba_ind_statistics
WHERE  owner = UPPER('&schema')
AND    object_type = 'INDEX'
AND   (last_analyzed IS NULL OR stale_stats = 'YES')
ORDER  BY table_name, index_name
FETCH FIRST 50 ROWS ONLY;

COLUMN total  FORMAT 99,990 HEADING 'Tables'
COLUMN stale  FORMAT 99,990 HEADING 'Stale'
COLUMN never  FORMAT 99,990 HEADING 'Never'
COLUMN locked FORMAT 99,990 HEADING 'Locked'
PROMPT
PROMPT Totals for the schema
SELECT COUNT(*) AS total,
       SUM(CASE WHEN stale_stats = 'YES' THEN 1 ELSE 0 END)      AS stale,
       SUM(CASE WHEN last_analyzed IS NULL THEN 1 ELSE 0 END)    AS never,
       SUM(CASE WHEN stattype_locked IS NOT NULL THEN 1 ELSE 0 END) AS locked
FROM   dba_tab_statistics
WHERE  owner = UPPER('&schema') AND object_type = 'TABLE' AND table_name NOT LIKE 'BIN$%';

COLUMN client_name FORMAT a36 HEADING 'Automatic task'
COLUMN status      FORMAT a10 HEADING 'Status'
COLUMN pref        FORMAT a40 HEADING 'Preference'
PROMPT
SELECT client_name, status FROM dba_autotask_client WHERE client_name = 'auto optimizer stats collection';
SELECT 'STALE_PERCENT = ' || DBMS_STATS.GET_PREFS('STALE_PERCENT', UPPER('&schema')) AS pref FROM dual
UNION ALL
SELECT 'ESTIMATE_PERCENT = ' || DBMS_STATS.GET_PREFS('ESTIMATE_PERCENT', UPPER('&schema')) FROM dual;

PROMPT
PROMPT Stale flags update every few minutes; for an exact picture first run (as a DBA):
PROMPT   EXEC DBMS_STATS.FLUSH_DATABASE_MONITORING_INFO;
PROMPT Gather only what is stale:
PROMPT   EXEC DBMS_STATS.GATHER_SCHEMA_STATS(ownname => '&schema', options => 'GATHER AUTO');
PROMPT Locked stats are usually locked on purpose (for example volatile staging tables). Check before unlocking.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con schema 1
SET TERMOUT OFF
@stats_health_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f stats_health_saved_settings.sql
