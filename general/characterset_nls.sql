-- =============================================================
-- Script   : characterset_nls.sql
-- Purpose  : Database and national character set, NLS settings at
--            database, instance and session level, time zone file
--            version, and columns using BYTE vs CHAR length semantics
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Any container. In a CDB the PDBs can have a different
--            character set from the root: run it in each PDB you care about.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @characterset_nls.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET characterset_nls_saved_settings.sql REPLACE
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
TTITLE LEFT 'Character set and NLS   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN parameter FORMAT a28 HEADING 'Parameter'
COLUMN db_value  FORMAT a30 HEADING 'Database'
COLUMN inst_val  FORMAT a30 HEADING 'Instance (init.ora)'
COLUMN sess_val  FORMAT a30 HEADING 'This session'
PROMPT
PROMPT NLS settings: database (fixed at creation) vs instance vs your session
SELECT d.parameter,
       d.value AS db_value,
       NVL(i.value, '-') AS inst_val,
       NVL(s.value, '-') AS sess_val
FROM   nls_database_parameters d
       LEFT JOIN nls_instance_parameters i ON i.parameter = d.parameter
       LEFT JOIN nls_session_parameters  s ON s.parameter = d.parameter
ORDER  BY CASE WHEN d.parameter IN ('NLS_CHARACTERSET', 'NLS_NCHAR_CHARACTERSET') THEN 0 ELSE 1 END,
          d.parameter;

COLUMN property_name  FORMAT a30 HEADING 'Property'
COLUMN property_value FORMAT a30 HEADING 'Value'
PROMPT
PROMPT Time zone settings (DST_PRIMARY_TT_VERSION should match the time zone file in use)
SELECT property_name, property_value
FROM   database_properties
WHERE  property_name IN ('DBTIMEZONE', 'DST_PRIMARY_TT_VERSION', 'DST_UPGRADE_STATE')
UNION ALL
SELECT 'Time zone file in use', filename || ' (version ' || version || ')'
FROM   v$timezone_file;

COLUMN semantics FORMAT a10       HEADING 'Semantics'
COLUMN cols      FORMAT 9,999,990 HEADING 'Columns'
COLUMN owners    FORMAT 9,990     HEADING 'Owners'
PROMPT
PROMPT Application CHAR/VARCHAR2 columns by length semantics (BYTE in AL32UTF8 = fewer characters fit)
SELECT DECODE(c.char_used, 'B', 'BYTE', 'C', 'CHAR') AS semantics,
       COUNT(*) AS cols,
       COUNT(DISTINCT c.owner) AS owners
FROM   dba_tab_columns c
       JOIN dba_users u ON u.username = c.owner AND u.oracle_maintained = 'N'
WHERE  c.data_type IN ('CHAR', 'VARCHAR2')
GROUP  BY c.char_used;

PROMPT
PROMPT AL32UTF8 is Oracle's recommended database character set. Changing it later needs a migration
PROMPT (Database Migration Assistant for Unicode, DMU), not just an ALTER DATABASE.
PROMPT Client output looks wrong (?, garbled accents)? Check NLS_LANG on the client first.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@characterset_nls_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f characterset_nls_saved_settings.sql
