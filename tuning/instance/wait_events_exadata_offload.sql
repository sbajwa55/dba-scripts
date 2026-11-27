-- =============================================================
-- Script   : wait_events_exadata_offload.sql
-- Purpose  : Top non-idle wait events since instance startup, time
--            model (DB time vs CPU), and Exadata efficiency: Smart
--            Scan, storage indexes and flash cache
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB, on each RAC instance (figures are
--            per instance). The Exadata section shows zeros on
--            non-Exadata systems.
-- Changes  : None (read-only). No AWR or Diagnostics Pack needed.
-- Client   : SQL*Plus      Usage: SQL> @wait_events_exadata_offload.sql
-- Notes    : Figures are cumulative since startup. For a specific
--            time window use AWR reports (Diagnostics Pack licence).
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET wait_events_exadata_offload_saved_settings.sql REPLACE
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
TTITLE LEFT 'Wait events and Exadata offload   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN stat_name FORMAT a32 HEADING 'Time model'
COLUMN hours     FORMAT 99,999,990.9 HEADING 'Hours'
COLUMN pct_db    FORMAT 990.9 HEADING '% of DB time'
PROMPT
PROMPT Where database time goes (since startup)
SELECT stat_name,
       ROUND(value / 3.6e9, 1)                                                    AS hours,
       ROUND(100 * value / NULLIF((SELECT value FROM v$sys_time_model WHERE stat_name = 'DB time'), 0), 1) AS pct_db
FROM   v$sys_time_model
WHERE  stat_name IN ('DB time', 'DB CPU', 'sql execute elapsed time', 'parse time elapsed',
                     'hard parse elapsed time', 'PL/SQL execution elapsed time')
ORDER  BY value DESC;

COLUMN event      FORMAT a40 HEADING 'Wait event'
COLUMN wait_class FORMAT a14 HEADING 'Class'
COLUMN waits      FORMAT 999,999,999,990 HEADING 'Waits'
COLUMN wait_hours FORMAT 9,999,990.9 HEADING 'Hours waited'
COLUMN avg_ms     FORMAT 99,990.99 HEADING 'Avg ms'
PROMPT
PROMPT Top 15 non-idle wait events (since startup)
SELECT event, wait_class, total_waits AS waits,
       ROUND(time_waited_micro / 3.6e9, 1)                         AS wait_hours,
       ROUND(time_waited_micro / NULLIF(total_waits, 0) / 1000, 2) AS avg_ms
FROM   v$system_event
WHERE  wait_class <> 'Idle'
ORDER  BY time_waited_micro DESC
FETCH  FIRST 15 ROWS ONLY;

COLUMN cells FORMAT 990 HEADING 'Storage cells seen'
PROMPT
PROMPT Exadata check (0 = not Exadata; the section below will show zeros)
SELECT COUNT(*) AS cells FROM v$cell;

COLUMN metric FORMAT a58 HEADING 'Exadata metric'
COLUMN gb     FORMAT 999,999,990.9 HEADING 'GB'
PROMPT
PROMPT Exadata I/O efficiency (since startup)
SELECT name AS metric, ROUND(value / 1073741824, 1) AS gb
FROM   v$sysstat
WHERE  name IN ('physical read total bytes',
                'cell physical IO bytes eligible for predicate offload',
                'cell physical IO interconnect bytes returned by smart scan',
                'cell physical IO bytes saved by storage index')
ORDER  BY name;

COLUMN ratio_name FORMAT a58 HEADING 'Ratio'
COLUMN pct        FORMAT 990.9 HEADING '%'
SELECT 'Smart Scan: eligible bytes NOT sent to the database' AS ratio_name,
       ROUND(100 * (1 - ss.value / NULLIF(el.value, 0)), 1)  AS pct
FROM   v$sysstat el, v$sysstat ss
WHERE  el.name = 'cell physical IO bytes eligible for predicate offload'
AND    ss.name = 'cell physical IO interconnect bytes returned by smart scan'
UNION ALL
SELECT 'Storage index: share of eligible bytes skipped',
       ROUND(100 * si.value / NULLIF(el.value, 0), 1)
FROM   v$sysstat el, v$sysstat si
WHERE  el.name = 'cell physical IO bytes eligible for predicate offload'
AND    si.name = 'cell physical IO bytes saved by storage index';
PROMPT
PROMPT Reading it: high "DB CPU" share = CPU-bound SQL; "User I/O" waits dominating = I/O-bound.
PROMPT On Exadata, "cell single block physical read" is the OLTP read; "cell smart table scan" is offloaded scanning.
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@wait_events_exadata_offload_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f wait_events_exadata_offload_saved_settings.sql

