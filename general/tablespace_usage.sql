-- =============================================================
-- Script   : tablespace_usage.sql
-- Purpose  : Show size, used and free space for each tablespace
-- Section  : General
-- Database : Oracle 12c, 19c, 21c
-- Run as   : A user with SELECT_CATALOG_ROLE (or SELECT ANY DICTIONARY)
-- Changes  : None (read-only)
-- Client   : SQL*Plus
-- Usage    : SQL> @tablespace_usage.sql
-- Notes    : - Covers permanent, undo and temporary tablespaces.
--            - "Max MB" is the size each tablespace can grow to with
--              autoextend; "% of Max" is what to watch.
--            - Your SQL*Plus settings are saved at the start and
--              restored at the end; column formats are cleared.
-- Where    : Multitenant (CDB) databases
--              * Run it in each PDB to see that PDB's tablespaces:
--                  SQL> ALTER SESSION SET CONTAINER = <PDB_NAME>;
--                  SQL> @tablespace_usage.sql
--              * Run it in CDB$ROOT to see the root's own tablespaces
--                (SYSTEM, SYSAUX, UNDOTBS1, TEMP, USERS of the root).
--              * The DBA_ views used here show only the current
--                container, so running it in CDB$ROOT does NOT include
--                the PDBs' tablespaces.
--            Non-CDB databases (and 12c non-multitenant)
--              * Run it normally; it shows every tablespace.
--            The report prints the container name at the top, so you
--            can always see where it ran.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================

-- ---------- 1. Save the current session settings --------------
SET TERMOUT OFF
STORE SET ts_usage_saved_settings.sql REPLACE
SET TERMOUT ON

-- ---------- 2. Formatting for this report only ----------------
SET PAGESIZE 100
SET LINESIZE 170
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET TRIMOUT ON
SET TRIMSPOOL ON
SET TAB OFF
SET UNDERLINE =

COLUMN tablespace_name FORMAT a24             HEADING 'Tablespace'
COLUMN ts_type         FORMAT a9              HEADING 'Type'
COLUMN files           FORMAT 990             HEADING 'Files'
COLUMN size_mb         FORMAT 999,999,990.9   HEADING 'Size MB'
COLUMN used_mb         FORMAT 999,999,990.9   HEADING 'Used MB'
COLUMN free_mb         FORMAT 999,999,990.9   HEADING 'Free MB'
COLUMN pct_used        FORMAT 990.9           HEADING 'Used %'
COLUMN max_mb          FORMAT 999,999,990.9   HEADING 'Max MB'
COLUMN pct_of_max      FORMAT 990.9           HEADING '% of Max'
COLUMN autoext         FORMAT a4              HEADING 'Auto'
COLUMN alert           FORMAT a10             HEADING 'Check'

BREAK ON REPORT
COMPUTE SUM LABEL 'Total' OF size_mb used_mb free_mb max_mb ON REPORT

-- Container and database name for the title
COLUMN con_name_col NEW_VALUE v_container NOPRINT
COLUMN db_name_col  NEW_VALUE v_dbname    NOPRINT
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name_col,
       SYS_CONTEXT('USERENV', 'DB_NAME')  AS db_name_col
FROM   dual;

TTITLE LEFT 'Tablespace usage   ' _DATE SKIP 1 -
       LEFT 'Database: ' v_dbname '   Container: ' v_container SKIP 1 -
       LEFT '========================================' SKIP 1

-- ---------- 3. The report --------------------------------------
WITH df AS (            -- permanent and undo datafiles
    SELECT tablespace_name,
           COUNT(*)                                   AS files,
           SUM(bytes)                                 AS bytes,
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes))) AS maxbytes,
           MAX(autoextensible)                        AS autoext
    FROM   dba_data_files
    GROUP  BY tablespace_name
),
fs AS (                 -- free space in permanent and undo tablespaces
    SELECT tablespace_name, SUM(bytes) AS free_bytes
    FROM   dba_free_space
    GROUP  BY tablespace_name
),
tf AS (                 -- temporary tempfiles
    SELECT tablespace_name,
           COUNT(*)                                   AS files,
           SUM(bytes)                                 AS bytes,
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes))) AS maxbytes,
           MAX(autoextensible)                        AS autoext
    FROM   dba_temp_files
    GROUP  BY tablespace_name
),
usage AS (
    SELECT d.tablespace_name, t.contents, d.files, d.bytes, d.maxbytes, d.autoext,
           d.bytes - NVL(f.free_bytes, 0)             AS used_bytes
    FROM   df d
           JOIN dba_tablespaces t ON t.tablespace_name = d.tablespace_name
           LEFT JOIN fs f         ON f.tablespace_name = d.tablespace_name
    UNION ALL
    SELECT x.tablespace_name, 'TEMPORARY', x.files, x.bytes, x.maxbytes, x.autoext,
           x.bytes - NVL(tfs.free_space, 0)
    FROM   tf x
           LEFT JOIN dba_temp_free_space tfs ON tfs.tablespace_name = x.tablespace_name
)
SELECT tablespace_name,
       contents                                              AS ts_type,
       files,
       ROUND(bytes / 1048576, 1)                             AS size_mb,
       ROUND(used_bytes / 1048576, 1)                        AS used_mb,
       ROUND((bytes - used_bytes) / 1048576, 1)              AS free_mb,
       ROUND(100 * used_bytes / NULLIF(bytes, 0), 1)         AS pct_used,
       ROUND(maxbytes / 1048576, 1)                          AS max_mb,
       ROUND(100 * used_bytes / NULLIF(maxbytes, 0), 1)      AS pct_of_max,
       autoext,
       CASE
           WHEN contents = 'PERMANENT'
            AND 100 * used_bytes / NULLIF(maxbytes, 0) >= 90 THEN '<-- HIGH'
           WHEN contents = 'PERMANENT'
            AND 100 * used_bytes / NULLIF(maxbytes, 0) >= 80 THEN '<-- watch'
       END                                                   AS alert
FROM   usage
ORDER  BY pct_of_max DESC NULLS LAST, tablespace_name;

PROMPT
PROMPT Notes: UNDO and TEMP space is reused automatically, so high usage there is often normal.
PROMPT        Watch "% of Max" for PERMANENT tablespaces: 80% = plan to add space, 90% = act now.
PROMPT

-- ---------- 4. Undo the formatting -----------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_container v_dbname

SET TERMOUT OFF
@ts_usage_saved_settings.sql
SET TERMOUT ON

-- Remove the temporary settings file
-- (Linux/Unix; on Windows change "rm -f" to "del")
HOST rm -f ts_usage_saved_settings.sql
