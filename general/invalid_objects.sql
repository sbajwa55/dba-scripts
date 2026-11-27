-- =============================================================
-- Script   : invalid_objects.sql
-- Purpose  : Things that are broken or switched off: invalid objects by
--            owner and type, unusable indexes and index partitions,
--            disabled constraints and triggers, and the components
--            in the registry that are not VALID
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB you want to check (or a non-CDB). Run it in each
--            PDB; CDB$ROOT shows the root only.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @invalid_objects.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET invalid_objects_saved_settings.sql REPLACE
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
TTITLE LEFT 'Invalid objects   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN owner       FORMAT a26     HEADING 'Owner'
COLUMN object_type FORMAT a24     HEADING 'Type'
COLUMN cnt         FORMAT 99,990  HEADING 'Invalid'
BREAK ON owner SKIP 1
PROMPT
PROMPT Invalid objects by owner and type
SELECT owner, object_type, COUNT(*) AS cnt
FROM   dba_objects
WHERE  status = 'INVALID'
GROUP  BY owner, object_type
ORDER  BY owner, object_type;
CLEAR BREAKS

COLUMN object_name FORMAT a36 HEADING 'Object'
COLUMN changed     FORMAT a15 HEADING 'Last DDL'
PROMPT
PROMPT First 40 invalid objects in application schemas
SELECT o.owner, o.object_name, o.object_type, TO_CHAR(o.last_ddl_time, 'DD-MON-YY HH24:MI') AS changed
FROM   dba_objects o JOIN dba_users u ON u.username = o.owner
WHERE  o.status = 'INVALID' AND u.oracle_maintained = 'N'
ORDER  BY o.owner, o.object_type, o.object_name
FETCH FIRST 40 ROWS ONLY;

COLUMN index_name FORMAT a40 HEADING 'Index (partition)'
COLUMN status     FORMAT a10 HEADING 'Status'
PROMPT
PROMPT Unusable indexes and index partitions
SELECT owner, index_name, status FROM dba_indexes WHERE status = 'UNUSABLE'
UNION ALL
SELECT index_owner, index_name || ' (' || partition_name || ')', status
FROM   dba_ind_partitions WHERE status = 'UNUSABLE'
UNION ALL
SELECT index_owner, index_name || ' (' || subpartition_name || ')', status
FROM   dba_ind_subpartitions WHERE status = 'UNUSABLE'
ORDER  BY 1, 2
FETCH FIRST 50 ROWS ONLY;

COLUMN what FORMAT a60 HEADING 'Constraint or trigger'
COLUMN kind FORMAT a14 HEADING 'Kind'
PROMPT
PROMPT Disabled constraints and triggers in application schemas
SELECT c.owner, c.table_name || '.' || c.constraint_name AS what,
       DECODE(c.constraint_type, 'P','Primary key', 'U','Unique', 'R','Foreign key', 'C','Check', c.constraint_type) AS kind
FROM   dba_constraints c JOIN dba_users u ON u.username = c.owner
WHERE  c.status = 'DISABLED' AND u.oracle_maintained = 'N' AND c.table_name NOT LIKE 'BIN$%'
UNION ALL
SELECT t.owner, t.table_name || '.' || t.trigger_name, 'Trigger'
FROM   dba_triggers t JOIN dba_users u ON u.username = t.owner
WHERE  t.status = 'DISABLED' AND u.oracle_maintained = 'N'
ORDER  BY 1, 2
FETCH FIRST 60 ROWS ONLY;

COLUMN comp_name FORMAT a40 HEADING 'Component'
COLUMN version   FORMAT a18 HEADING 'Version'
PROMPT
PROMPT Database components not VALID (should be no rows)
SELECT comp_name, version, status FROM dba_registry WHERE status NOT IN ('VALID', 'OPTION OFF');

PROMPT
PROMPT Recompile everything invalid (as SYS, in each container):  SQL> @?/rdbms/admin/utlrp.sql
PROMPT Rebuild an unusable index:  ALTER INDEX <owner>.<index> REBUILD ONLINE;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@invalid_objects_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f invalid_objects_saved_settings.sql
