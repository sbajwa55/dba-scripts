-- =============================================================
-- Script   : rac_cluster_status.sql
-- Purpose  : RAC health from the database: instances, services by
--            instance, sessions per node, interconnect, and global
--            cache (GC) wait times
-- Section  : High Availability / RAC
-- Database : Oracle 19c, 21c RAC (CDB or non-CDB; Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Any one instance (uses GV$ views to see all nodes).
--            CDB: run in CDB$ROOT to see services of all PDBs.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @rac_cluster_status.sql
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET rac_cluster_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'RAC cluster status   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN inst_id       FORMAT 99  HEADING 'Inst'
COLUMN instance_name FORMAT a14 HEADING 'Instance'
COLUMN host_name     FORMAT a26 HEADING 'Host'
COLUMN status        FORMAT a8  HEADING 'Status'
COLUMN startup       FORMAT a17 HEADING 'Started'
COLUMN sessions      FORMAT 99,990 HEADING 'Sessions'
COLUMN active        FORMAT 99,990 HEADING 'Active'
PROMPT
PROMPT Instances and sessions per node
SELECT i.inst_id, i.instance_name, i.host_name, i.status,
       TO_CHAR(i.startup_time, 'DD-MON-YY HH24:MI') AS startup,
       (SELECT COUNT(*) FROM gv$session s WHERE s.inst_id = i.inst_id AND s.type = 'USER') AS sessions,
       (SELECT COUNT(*) FROM gv$session s WHERE s.inst_id = i.inst_id AND s.type = 'USER'
                                         AND s.status = 'ACTIVE') AS active
FROM   gv$instance i
ORDER  BY i.inst_id;

COLUMN service   FORMAT a40 HEADING 'Service'
COLUMN running_on FORMAT a40 HEADING 'Running on instances'
PROMPT
PROMPT Services and where they run (a service missing from a node may need relocating)
SELECT s.name AS service,
       LISTAGG(i.instance_name, ', ') WITHIN GROUP (ORDER BY i.inst_id) AS running_on
FROM   gv$active_services s
       JOIN gv$instance i ON i.inst_id = s.inst_id
WHERE  s.name NOT LIKE 'SYS$%'
GROUP  BY s.name
ORDER  BY s.name;

COLUMN ic_name   FORMAT a10 HEADING 'Interface'
COLUMN ip        FORMAT a16 HEADING 'IP address'
COLUMN source    FORMAT a32 HEADING 'Source'
PROMPT
PROMPT Private interconnect in use
SELECT inst_id, name AS ic_name, ip_address AS ip, source
FROM   gv$cluster_interconnects
ORDER  BY inst_id, name;

COLUMN event     FORMAT a36 HEADING 'GC wait event'
COLUMN waits     FORMAT 999,999,999,990 HEADING 'Waits'
COLUMN avg_ms    FORMAT 9,990.99 HEADING 'Avg ms'
PROMPT
PROMPT Global cache waits since startup (average above about 1 ms deserves a look; Exadata is often well below)
SELECT inst_id, event, total_waits AS waits,
       ROUND(time_waited_micro / NULLIF(total_waits, 0) / 1000, 2) AS avg_ms
FROM   gv$system_event
WHERE  event IN ('gc cr block 2-way', 'gc current block 2-way', 'gc cr block 3-way',
                 'gc current block 3-way', 'gc cr block busy', 'gc current block busy',
                 'gc buffer busy acquire', 'gc buffer busy release')
AND    total_waits > 0
ORDER  BY event, inst_id;
PROMPT
PROMPT For cluster stack health (CRS, ASM disk groups, voting disks) run ha/rac/crs_asm_status.ksh on a node.
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@rac_cluster_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f rac_cluster_status_saved_settings.sql

