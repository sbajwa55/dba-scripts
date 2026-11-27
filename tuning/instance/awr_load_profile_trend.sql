-- =============================================================
-- Script   : awr_load_profile_trend.sql
-- Purpose  : Load trend from AWR for the last N days, one row per snapshot:
--            average active sessions, host CPU, IOPS, redo, transactions
--            and executions per second. Shows when the database is busy.
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB. RAC: one row per instance per snapshot.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @awr_load_profile_trend.sql
-- Settings : "days_back" = days of AWR history to show.
-- Notes    : Uses ASH/AWR views: needs the Oracle Diagnostics Pack licence
--            (Enterprise Edition). Do not run it if you are not licensed.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 2
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET awr_load_profile_trend_saved_settings.sql REPLACE
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
TTITLE LEFT 'AWR load profile trend   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN snap_end FORMAT a15      HEADING 'Snapshot end'
COLUMN inst     FORMAT 990      HEADING 'Inst'
COLUMN aas      FORMAT 9,990.0  HEADING 'Avg active'
COLUMN aas_max  FORMAT 9,990.0  HEADING 'Max active'
COLUMN cpu      FORMAT 990      HEADING 'Host CPU %'
COLUMN iops     FORMAT 999,990  HEADING 'IOPS'
COLUMN redo_mb  FORMAT 9,990.0  HEADING 'Redo MB/s'
COLUMN tps      FORMAT 99,990   HEADING 'Trans/s'
COLUMN execs    FORMAT 9,999,990 HEADING 'Execs/s'
BREAK ON inst SKIP 1

PROMPT
PROMPT Load per AWR snapshot, last &days_back days
SELECT m.instance_number AS inst,
       TO_CHAR(MAX(m.end_time), 'DD-MON HH24:MI') AS snap_end,
       ROUND(MAX(DECODE(m.metric_name, 'Average Active Sessions', m.average)), 1)        AS aas,
       ROUND(MAX(DECODE(m.metric_name, 'Average Active Sessions', m.maxval)), 1)         AS aas_max,
       ROUND(MAX(DECODE(m.metric_name, 'Host CPU Utilization (%)', m.average)))          AS cpu,
       ROUND(MAX(DECODE(m.metric_name, 'I/O Requests per Second', m.average)))           AS iops,
       ROUND(MAX(DECODE(m.metric_name, 'Redo Generated Per Sec', m.average)) / POWER(1024,2), 1) AS redo_mb,
       ROUND(MAX(DECODE(m.metric_name, 'User Transaction Per Sec', m.average)))          AS tps,
       ROUND(MAX(DECODE(m.metric_name, 'Executions Per Sec', m.average)))                AS execs
FROM   dba_hist_sysmetric_summary m
WHERE  m.dbid = (SELECT dbid FROM v$database)
AND    m.end_time > SYSDATE - &days_back
AND    m.metric_name IN ('Average Active Sessions', 'Host CPU Utilization (%)', 'I/O Requests per Second',
                         'Redo Generated Per Sec', 'User Transaction Per Sec', 'Executions Per Sec')
GROUP  BY m.instance_number, m.snap_id
ORDER  BY m.instance_number, m.snap_id;
CLEAR BREAKS

COLUMN cpus FORMAT 990 HEADING 'CPUs'
PROMPT
PROMPT CPU count per instance (compare with "Max active")
SELECT inst_id AS inst, value AS cpus FROM gv$parameter WHERE name = 'cpu_count' ORDER BY inst_id;

PROMPT
PROMPT Pick the busiest snapshot pair and run an AWR report for it:  SQL> @?/rdbms/admin/awrrpt.sql
PROMPT "Avg active" well above the CPU count means sessions are queuing for CPU or waiting on I/O.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@awr_load_profile_trend_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f awr_load_profile_trend_saved_settings.sql
