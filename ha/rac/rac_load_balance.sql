-- =============================================================
-- Script   : rac_load_balance.sql
-- Purpose  : Is the work spread evenly across the nodes? Per instance
--            load (active sessions, CPU, logons), sessions per service on
--            each instance, service settings (goal, failover, TAC), and
--            services that are not running anywhere
-- Section  : High Availability / RAC
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Any instance of the RAC database. CDB$ROOT to see the
--            services of every PDB.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @rac_load_balance.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET rac_load_balance_saved_settings.sql REPLACE
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
TTITLE LEFT 'RAC load balance   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN inst      FORMAT 990     HEADING 'Inst'
COLUMN host      FORMAT a20     HEADING 'Host'
COLUMN aas       FORMAT 990.0   HEADING 'Avg active'
COLUMN cpu       FORMAT 990     HEADING 'Host CPU %'
COLUMN logons    FORMAT 9,990.0 HEADING 'Logons/s'
COLUMN sess      FORMAT 99,990  HEADING 'Sessions'
PROMPT
PROMPT Load per instance over the last minute (a big difference between nodes = check the services)
SELECT m.inst_id AS inst,
       (SELECT host_name FROM gv$instance i WHERE i.inst_id = m.inst_id) AS host,
       ROUND(MAX(DECODE(metric_name, 'Average Active Sessions', value)), 1)    AS aas,
       ROUND(MAX(DECODE(metric_name, 'Host CPU Utilization (%)', value)))      AS cpu,
       ROUND(MAX(DECODE(metric_name, 'Logons Per Sec', value)), 1)             AS logons,
       (SELECT COUNT(*) FROM gv$session s WHERE s.inst_id = m.inst_id AND s.type = 'USER') AS sess
FROM   gv$sysmetric m
WHERE  m.group_id = 2
AND    m.metric_name IN ('Average Active Sessions', 'Host CPU Utilization (%)', 'Logons Per Sec')
GROUP  BY m.inst_id
ORDER  BY m.inst_id;

COLUMN service   FORMAT a30 HEADING 'Service'
COLUMN by_inst   FORMAT a60 HEADING 'Sessions by instance (inst=sessions)'
PROMPT
PROMPT User sessions per service and instance
SELECT service_name AS service,
       LISTAGG(inst_id || '=' || cnt, '  ') WITHIN GROUP (ORDER BY inst_id) AS by_inst
FROM  (SELECT service_name, inst_id, COUNT(*) cnt FROM gv$session
       WHERE type = 'USER' GROUP BY service_name, inst_id)
GROUP  BY service_name
ORDER  BY service_name;

COLUMN goal     FORMAT a10 HEADING 'Goal'
COLUMN clb      FORMAT a6  HEADING 'CLB'
COLUMN failover FORMAT a12 HEADING 'Failover'
COLUMN commit_o FORMAT a7  HEADING 'Commit outcome'
COLUMN notify   FORMAT a7  HEADING 'FAN (AQ)'
COLUMN running  FORMAT a20 HEADING 'Running on'
PROMPT
PROMPT Application services: settings and where they run (empty "Running on" = service is down)
SELECT s.name AS service, s.goal, s.clb_goal AS clb, s.failover_type AS failover,
       s.commit_outcome AS commit_o, s.aq_ha_notifications AS notify,
       (SELECT LISTAGG(a.inst_id, ',') WITHIN GROUP (ORDER BY a.inst_id)
        FROM gv$active_services a WHERE a.name = s.name) AS running
FROM   cdb_services s
WHERE  s.name NOT LIKE 'SYS$%'
AND    s.name NOT LIKE '%XDB'
AND    s.name NOT IN (SELECT value FROM v$parameter WHERE name = 'db_unique_name')
AND    s.network_name IS NOT NULL
ORDER  BY running NULLS FIRST, s.name;

PROMPT
PROMPT Connect through SCAN with services, not instance names, so the listener can balance the load.
PROMPT Failover TRANSACTION + Commit outcome YES = Application Continuity / TAC is configured.
PROMPT Service placement and failover from Clusterware: ha/rac/rac_services_check.ksh
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@rac_load_balance_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f rac_load_balance_saved_settings.sql
