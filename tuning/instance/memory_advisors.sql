-- =============================================================
-- Script   : memory_advisors.sql
-- Purpose  : SGA and PGA sizing: current memory areas, what the advisors
--            predict for bigger or smaller SGA/PGA, PGA over-allocation,
--            and recent automatic memory resize operations
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB, on each RAC instance (advisors are
--            per instance).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @memory_advisors.sql
-- Settings : "resize_days" = days of resize history to show.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE resize_days = 3
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET memory_advisors_saved_settings.sql REPLACE
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
TTITLE LEFT 'Memory advisors   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN name   FORMAT a36        HEADING 'SGA component'
COLUMN mb     FORMAT 9,999,990  HEADING 'MB'
COLUMN resizeable FORMAT a4     HEADING 'Resz'
PROMPT
PROMPT Current SGA components
SELECT name, ROUND(bytes / POWER(1024,2)) AS mb, resizeable
FROM   v$sgainfo
ORDER  BY bytes DESC;

COLUMN sga_mb     FORMAT 9,999,990 HEADING 'SGA MB'
COLUMN factor     FORMAT 90.00     HEADING 'Factor'
COLUMN db_time    FORMAT 990.0     HEADING 'DB time %'
COLUMN phys_reads FORMAT 990.0     HEADING 'Phys reads %'
COLUMN flag       FORMAT a12       HEADING ' '
PROMPT
PROMPT SGA target advice (100% = today; lower % = less DB time / fewer reads)
SELECT a.sga_size AS sga_mb,
       a.sga_size_factor AS factor,
       ROUND(a.estd_db_time      / NULLIF(c.estd_db_time, 0)      * 100, 1) AS db_time,
       ROUND(a.estd_physical_reads / NULLIF(c.estd_physical_reads, 0) * 100, 1) AS phys_reads,
       CASE WHEN a.sga_size_factor = 1 THEN '<-- current' END AS flag
FROM   v$sga_target_advice a
       CROSS JOIN (SELECT estd_db_time, estd_physical_reads FROM v$sga_target_advice WHERE sga_size_factor = 1) c
ORDER  BY a.sga_size;

COLUMN pga_mb   FORMAT 9,999,990 HEADING 'PGA target MB'
COLUMN hit_pct  FORMAT 990       HEADING 'Cache hit %'
COLUMN overallc FORMAT 9,999,990 HEADING 'Over-alloc'
PROMPT
PROMPT PGA target advice (choose the smallest size with Over-alloc = 0 and a high hit %)
SELECT ROUND(pga_target_for_estimate / POWER(1024,2)) AS pga_mb,
       pga_target_factor            AS factor,
       estd_pga_cache_hit_percentage AS hit_pct,
       estd_overalloc_count          AS overallc,
       CASE WHEN pga_target_factor = 1 THEN '<-- current' END AS flag
FROM   v$pga_target_advice
ORDER  BY pga_target_for_estimate;

COLUMN stat  FORMAT a40         HEADING 'PGA statistic'
COLUMN value FORMAT 999,999,990 HEADING 'Value (MB or count)'
PROMPT
PROMPT PGA usage since startup
SELECT name AS stat,
       CASE WHEN unit = 'bytes' THEN ROUND(value / POWER(1024,2)) ELSE value END AS value
FROM   v$pgastat
WHERE  name IN ('aggregate PGA target parameter', 'total PGA allocated', 'maximum PGA allocated',
                'total PGA inuse', 'over allocation count', 'cache hit percentage');

COLUMN component FORMAT a28 HEADING 'Component'
COLUMN oper_type FORMAT a10 HEADING 'Change'
COLUMN from_mb   FORMAT 9,999,990 HEADING 'From MB'
COLUMN to_mb     FORMAT 9,999,990 HEADING 'To MB'
COLUMN started   FORMAT a17 HEADING 'Started'
PROMPT
PROMPT Automatic resize operations in the last &resize_days days (frequent shrink/grow = memory pressure)
SELECT component, oper_type,
       ROUND(initial_size / POWER(1024,2)) AS from_mb,
       ROUND(final_size   / POWER(1024,2)) AS to_mb,
       TO_CHAR(start_time, 'DD-MON-YY HH24:MI') AS started
FROM   v$memory_resize_ops
WHERE  start_time > SYSDATE - &resize_days
AND    oper_type IN ('GROW', 'SHRINK')
ORDER  BY start_time DESC
FETCH FIRST 40 ROWS ONLY;

PROMPT
PROMPT Advice is only as good as the workload since startup: check it after a busy period.
PROMPT "over allocation count" > 0 means PGA_AGGREGATE_TARGET is too small for the work being done.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con resize_days
SET TERMOUT OFF
@memory_advisors_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f memory_advisors_saved_settings.sql
