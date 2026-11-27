-- =============================================================
-- Script   : gg_supplemental_logging.sql
-- Purpose  : Is a schema ready to replicate? Database, schema and table
--            level supplemental logging, tables with no primary or unique
--            key, and tables GoldenGate cannot fully support
-- Section  : High Availability / GoldenGate
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The SOURCE PDB (or non-CDB) that holds the schema; database-
--            level logging is also shown for the CDB.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @gg_supplemental_logging.sql <SCHEMA>
-- Settings : Schema name is the first argument.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE schema = '&1'
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET gg_supplemental_logging_saved_settings.sql REPLACE
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
TTITLE LEFT 'GoldenGate supplemental logging   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN log_mode FORMAT a12 HEADING 'Log mode'
COLUMN force_l  FORMAT a6  HEADING 'Force'
COLUMN supp_min FORMAT a8  HEADING 'Supp min'
COLUMN supp_pk  FORMAT a6  HEADING 'All PK'
COLUMN supp_ui  FORMAT a6  HEADING 'All UI'
COLUMN supp_all FORMAT a7  HEADING 'All col'
COLUMN gg_param FORMAT a12 HEADING 'enable_goldengate_replication'
PROMPT
PROMPT Database-level settings (expect ARCHIVELOG, YES, YES; ALL PK/UI only if you chose database-wide logging)
SELECT log_mode, force_logging AS force_l, supplemental_log_data_min AS supp_min,
       supplemental_log_data_pk AS supp_pk, supplemental_log_data_ui AS supp_ui,
       supplemental_log_data_all AS supp_all,
       (SELECT value FROM v$parameter WHERE name = 'enable_goldengate_replication') AS gg_param
FROM   v$database;

COLUMN schema_name FORMAT a24 HEADING 'Schema with SCHEMATRANDATA'
COLUMN prepared    FORMAT a15 HEADING 'Prepared'
PROMPT
PROMPT Schema-level logging (ADD SCHEMATRANDATA) for &schema
SELECT schema_name, TO_CHAR(timestamp, 'DD-MON-YY HH24:MI') AS prepared,
       supplemental_log_data_pk AS supp_pk, supplemental_log_data_ui AS supp_ui, supplemental_log_data_all AS supp_all
FROM   dba_capture_prepared_schemas
WHERE  schema_name = UPPER('&schema');

COLUMN tabs    FORMAT 99,990 HEADING 'Tables'
COLUMN logged  FORMAT 99,990 HEADING 'With log group (TRANDATA)'
PROMPT
PROMPT Table-level logging (ADD TRANDATA) in &schema
SELECT COUNT(*) AS tabs,
       COUNT(DISTINCT g.table_name) AS logged
FROM   dba_tables t
       LEFT JOIN dba_log_groups g ON g.owner = t.owner AND g.table_name = t.table_name
WHERE  t.owner = UPPER('&schema') AND t.temporary = 'N' AND t.nested = 'NO' AND t.table_name NOT LIKE 'BIN$%';

COLUMN table_name FORMAT a32 HEADING 'Table without PK or unique key'
COLUMN num_rows   FORMAT 999,999,999,990 HEADING 'Rows (stats)'
PROMPT
PROMPT Tables with no primary key and no usable unique key (GoldenGate must log ALL columns: slow, risky)
SELECT t.table_name, t.num_rows
FROM   dba_tables t
WHERE  t.owner = UPPER('&schema') AND t.temporary = 'N' AND t.nested = 'NO' AND t.table_name NOT LIKE 'BIN$%'
AND    NOT EXISTS (SELECT 1 FROM dba_constraints c
                   WHERE c.owner = t.owner AND c.table_name = t.table_name
                   AND   c.constraint_type IN ('P', 'U') AND c.status = 'ENABLED')
ORDER  BY t.num_rows DESC NULLS LAST
FETCH FIRST 50 ROWS ONLY;

COLUMN support_mode FORMAT a10 HEADING 'Support'
COLUMN explanation  FORMAT a60 HEADING 'Meaning'
PROMPT
PROMPT Tables GoldenGate cannot capture natively (FULL = fine; ID KEY = fetch needed; NONE = not supported)
SELECT object_name AS table_name, support_mode,
       DECODE(support_mode, 'ID KEY', 'Captured, but needs fetch from the database for some columns',
                            'NONE',   'Not supported by integrated Extract - exclude or replicate another way',
                            'PLSQL',  'Supported through procedural replication only', support_mode) AS explanation
FROM   dba_goldengate_support_mode
WHERE  owner = UPPER('&schema') AND support_mode <> 'FULL'
ORDER  BY support_mode, object_name;

PROMPT
PROMPT Enable logging from GGSCI / Admin Client after DBLOGIN:
PROMPT   ADD SCHEMATRANDATA &schema ALLCOLS      (or ADD TRANDATA &schema..* for table level)
PROMPT Tables without a key: add a primary key, or define KEYCOLS in the Extract and Replicat.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con schema 1
SET TERMOUT OFF
@gg_supplemental_logging_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f gg_supplemental_logging_saved_settings.sql
