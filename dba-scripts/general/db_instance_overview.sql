-- =============================================================
-- Script   : db_instance_overview.sql
-- Purpose  : One-page overview: database role and modes, every
--            instance (RAC), PDBs, character set and last patches
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC, Data Guard, Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see all PDBs. Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @db_instance_overview.sql
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET db_instance_overview_saved_settings.sql REPLACE
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
TTITLE LEFT 'Database overview   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN name            FORMAT a10 HEADING 'DB name'
COLUMN db_unique_name  FORMAT a16 HEADING 'Unique name'
COLUMN database_role   FORMAT a16 HEADING 'Role'
COLUMN open_mode       FORMAT a20 HEADING 'Open mode'
COLUMN log_mode        FORMAT a12 HEADING 'Log mode'
COLUMN force_logging   FORMAT a7  HEADING 'Force'
COLUMN flashback_on    FORMAT a9  HEADING 'Flashback'
COLUMN protection_mode FORMAT a20 HEADING 'Protection'
COLUMN cdb             FORMAT a3  HEADING 'CDB'
PROMPT
PROMPT Database
SELECT name, db_unique_name, database_role, open_mode, log_mode, force_logging,
       flashback_on, protection_mode, cdb
FROM   v$database;

COLUMN inst_id       FORMAT 99   HEADING 'Inst'
COLUMN instance_name FORMAT a14  HEADING 'Instance'
COLUMN host_name     FORMAT a26  HEADING 'Host'
COLUMN status        FORMAT a8   HEADING 'Status'
COLUMN startup       FORMAT a17  HEADING 'Started'
COLUMN up_days       FORMAT 9,990.9 HEADING 'Up days'
COLUMN version_full  FORMAT a12  HEADING 'Version'
PROMPT
PROMPT Instances (all RAC nodes)
SELECT inst_id, instance_name, host_name, status,
       TO_CHAR(startup_time, 'DD-MON-YY HH24:MI') AS startup,
       ROUND(SYSDATE - startup_time, 1)           AS up_days,
       version_full
FROM   gv$instance
ORDER  BY inst_id;

COLUMN pdb_mode  FORMAT a12 HEADING 'Open mode'
COLUMN pdb_count FORMAT 990 HEADING 'PDBs'
PROMPT
PROMPT PDBs by open mode (no rows = non-CDB)
SELECT open_mode AS pdb_mode, COUNT(*) AS pdb_count
FROM   v$pdbs
WHERE  name <> 'PDB$SEED'
GROUP  BY open_mode;

COLUMN parameter FORMAT a26 HEADING 'Setting'
COLUMN value     FORMAT a40 HEADING 'Value'
PROMPT
PROMPT Key settings
SELECT parameter, value FROM nls_database_parameters
WHERE  parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET')
UNION ALL
SELECT name, display_value FROM v$parameter
WHERE  name IN ('cluster_database', 'sga_target', 'pga_aggregate_target', 'db_recovery_file_dest_size',
                'enable_goldengate_replication', 'dg_broker_start');

COLUMN patch_id    FORMAT 999999999 HEADING 'Patch'
COLUMN action      FORMAT a10 HEADING 'Action'
COLUMN pstatus     FORMAT a10 HEADING 'Status'
COLUMN applied     FORMAT a17 HEADING 'Applied'
COLUMN description FORMAT a70 HEADING 'Description' TRUNCATED
PROMPT
PROMPT Last 5 SQL patches (datapatch)
SELECT patch_id, action, status AS pstatus,
       TO_CHAR(action_time, 'DD-MON-YY HH24:MI') AS applied, description
FROM   dba_registry_sqlpatch
ORDER  BY action_time DESC
FETCH  FIRST 5 ROWS ONLY;
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@db_instance_overview_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f db_instance_overview_saved_settings.sql

