-- =============================================================
-- Script   : index_usage.sql
-- Purpose  : Index review for one schema: indexes with no recorded use
--            (candidates to drop), their size, and foreign keys with no
--            supporting index (a common cause of lock waits)
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB (or non-CDB) that holds the schema.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @index_usage.sql <SCHEMA>
-- Settings : Schema name is the first argument.
-- Notes    : Uses DBA_INDEX_USAGE (12.2+), which Oracle fills by sampling
--            and flushes every 15 minutes. "No use" means no use was
--            recorded since tracking started, not proof it is never used.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE schema = '&1'
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET index_usage_saved_settings.sql REPLACE
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
TTITLE LEFT 'Index usage   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN index_name FORMAT a32       HEADING 'Index'
COLUMN table_name FORMAT a30       HEADING 'Table'
COLUMN size_mb    FORMAT 9,999,990 HEADING 'Size MB'
COLUMN accesses   FORMAT 999,999,990 HEADING 'Accesses'
COLUMN last_used  FORMAT a15       HEADING 'Last used'
PROMPT
PROMPT Indexes with no recorded use in schema &schema (primary key and unique indexes excluded)
SELECT i.index_name, i.table_name,
       ROUND(NVL(SUM(s.bytes), 0) / POWER(1024,2)) AS size_mb,
       NVL(MAX(u.total_access_count), 0) AS accesses,
       NVL(TO_CHAR(MAX(u.last_used), 'DD-MON-YY HH24:MI'), 'never seen') AS last_used
FROM   dba_indexes i
       LEFT JOIN dba_index_usage u ON u.owner = i.owner AND u.name = i.index_name
       LEFT JOIN dba_segments    s ON s.owner = i.owner AND s.segment_name = i.index_name
WHERE  i.owner = UPPER('&schema')
AND    i.uniqueness = 'NONUNIQUE'
AND    i.index_type NOT IN ('LOB', 'IOT - TOP')
AND    NOT EXISTS (SELECT 1 FROM dba_constraints c
                   WHERE c.owner = i.owner AND c.index_name = i.index_name)
GROUP  BY i.index_name, i.table_name
HAVING NVL(MAX(u.total_access_count), 0) = 0
ORDER  BY size_mb DESC
FETCH FIRST 50 ROWS ONLY;

COLUMN constraint_name FORMAT a30 HEADING 'Foreign key'
COLUMN columns         FORMAT a45 HEADING 'Columns'
PROMPT
PROMPT Foreign keys whose columns are not at the start of any index
SELECT c.table_name, c.constraint_name,
       LISTAGG(cc.column_name, ', ') WITHIN GROUP (ORDER BY cc.position) AS columns
FROM   dba_constraints c
       JOIN dba_cons_columns cc ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
WHERE  c.owner = UPPER('&schema')
AND    c.constraint_type = 'R'
AND    NOT EXISTS (
         SELECT 1 FROM dba_ind_columns ic
         WHERE  ic.table_owner = c.owner AND ic.table_name = c.table_name
         AND    ic.column_position = 1
         AND    ic.column_name = (SELECT cc1.column_name FROM dba_cons_columns cc1
                                  WHERE cc1.owner = c.owner AND cc1.constraint_name = c.constraint_name
                                  AND   cc1.position = 1))
GROUP  BY c.table_name, c.constraint_name
ORDER  BY c.table_name;

PROMPT
PROMPT The foreign key check looks at the first column only; review multi-column keys by hand.
PROMPT Before dropping an index, make it invisible for a full business cycle (month end, year end):
PROMPT   ALTER INDEX &schema..<index_name> INVISIBLE;     -- undo: ALTER INDEX ... VISIBLE;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con schema 1
SET TERMOUT OFF
@index_usage_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f index_usage_saved_settings.sql
