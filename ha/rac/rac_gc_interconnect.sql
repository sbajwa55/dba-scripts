-- =============================================================
-- Script   : rac_gc_interconnect.sql
-- Purpose  : Interconnect and global cache in depth: blocks sent and
--            received per instance, average receive times, lost and
--            corrupt blocks, interconnect traffic, and the segments with
--            the most cluster waits (hot blocks shared between nodes)
-- Section  : High Availability / RAC
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Any instance of the RAC database (GV$ covers all).
--            CDB$ROOT to see segments in every PDB.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @rac_gc_interconnect.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET rac_gc_interconnect_saved_settings.sql REPLACE
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
TTITLE LEFT 'RAC global cache and interconnect   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN inst       FORMAT 990        HEADING 'Inst'
COLUMN cr_recv    FORMAT 999,999,999,990 HEADING 'CR blocks recv'
COLUMN cr_ms      FORMAT 990.00     HEADING 'CR ms'
COLUMN cur_recv   FORMAT 999,999,999,990 HEADING 'Current blocks recv'
COLUMN cur_ms     FORMAT 990.00     HEADING 'Current ms'
COLUMN lost       FORMAT 9,999,990  HEADING 'Lost'
COLUMN corrupt    FORMAT 9,990      HEADING 'Corrupt'
PROMPT
PROMPT Global cache per instance since startup (receive time > ~1 ms or any lost blocks = interconnect problem)
SELECT inst_id AS inst,
       SUM(DECODE(name, 'gc cr blocks received', value))      AS cr_recv,
       ROUND(SUM(DECODE(name, 'gc cr block receive time', value)) * 10 /
             NULLIF(SUM(DECODE(name, 'gc cr blocks received', value)), 0), 2)      AS cr_ms,
       SUM(DECODE(name, 'gc current blocks received', value)) AS cur_recv,
       ROUND(SUM(DECODE(name, 'gc current block receive time', value)) * 10 /
             NULLIF(SUM(DECODE(name, 'gc current blocks received', value)), 0), 2) AS cur_ms,
       SUM(DECODE(name, 'gc blocks lost', value))             AS lost,
       SUM(DECODE(name, 'gc blocks corrupt', value))          AS corrupt
FROM   gv$sysstat
WHERE  name IN ('gc cr blocks received', 'gc cr block receive time', 'gc current blocks received',
                'gc current block receive time', 'gc blocks lost', 'gc blocks corrupt')
GROUP  BY inst_id
ORDER  BY inst_id;

COLUMN mb_recv FORMAT 9,999,990.0 HEADING 'GC MB/s received (last minute)'
PROMPT
SELECT inst_id AS inst,
       ROUND(SUM(CASE WHEN metric_name IN ('GC CR Block Received Per Second', 'GC Current Block Received Per Second')
                      THEN value END) *
             (SELECT TO_NUMBER(value) FROM v$parameter WHERE name = 'db_block_size') / POWER(1024,2), 1) AS mb_recv
FROM   gv$sysmetric
WHERE  group_id = 2
GROUP  BY inst_id
ORDER  BY inst_id;

COLUMN event  FORMAT a32 HEADING 'Cluster wait event'
COLUMN waits  FORMAT 999,999,999,990 HEADING 'Waits'
COLUMN avg_ms FORMAT 9,990.00 HEADING 'Avg ms'
PROMPT
PROMPT Top cluster-class waits (all instances)
SELECT event, SUM(total_waits) AS waits,
       ROUND(SUM(time_waited_micro) / NULLIF(SUM(total_waits), 0) / 1000, 2) AS avg_ms
FROM   gv$system_event
WHERE  wait_class = 'Cluster'
GROUP  BY event
ORDER  BY SUM(time_waited_micro) DESC
FETCH FIRST 10 ROWS ONLY;

COLUMN segment   FORMAT a50 HEADING 'Segment'
COLUMN stat      FORMAT a28 HEADING 'Statistic'
COLUMN val       FORMAT 999,999,999,990 HEADING 'Value'
PROMPT
PROMPT Segments with the most global cache activity (hot spots shared between nodes)
SELECT owner || '.' || object_name || NVL2(subobject_name, ' (' || subobject_name || ')', '') AS segment,
       statistic_name AS stat, SUM(value) AS val
FROM   gv$segment_statistics
WHERE  statistic_name IN ('gc buffer busy', 'gc cr blocks received', 'gc current blocks received')
AND    value > 0
GROUP  BY owner, object_name, subobject_name, statistic_name
ORDER  BY val DESC
FETCH FIRST 15 ROWS ONLY;

PROMPT
PROMPT Lost blocks: check the private network (MTU/jumbo frames match on every node, NIC errors in netstat -s).
PROMPT A hot segment: use services to keep one application on one node, or reverse-key / hash-partition its index.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@rac_gc_interconnect_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f rac_gc_interconnect_saved_settings.sql
