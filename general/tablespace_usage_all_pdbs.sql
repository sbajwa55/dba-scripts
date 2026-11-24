-- =============================================================
-- Script   : tablespace_usage_all_pdbs.sql
-- Purpose  : Show size, used and free space for every tablespace in
--            every container (CDB$ROOT and all open PDBs), plus a
--            per-PDB summary
-- Section  : General
-- Database : Oracle 12c, 19c, 21c (multitenant / CDB only)
-- Run as   : A common user in CDB$ROOT, e.g. SYS AS SYSDBA or a C##
--            user with SELECT_CATALOG_ROLE granted CONTAINER=ALL
-- Changes  : None (read-only)
-- Client   : SQL*Plus
-- Usage    : SQL> ALTER SESSION SET CONTAINER = CDB$ROOT;
--            SQL> @tablespace_usage_all_pdbs.sql
-- Where    : Run it in CDB$ROOT only. The CDB_ views it uses return
--            every container's data only from the root; inside a PDB
--            they show just that PDB. The script warns you if you are
--            not in CDB$ROOT.
--            PDBs that are MOUNTED (not open) cannot be read and are
--            listed at the end so you know they were skipped.
--            For a single PDB, use tablespace_usage.sql inside that PDB.
-- Notes    : "% of Max" is usage against the autoextend limit, the
--            number to watch. Your SQL*Plus settings are saved at the
--            start and restored at the end.
--            On databases with many PDBs, CDB_ views can take a while.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================

-- ---------- 1. Save the current session settings --------------
SET TERMOUT OFF
STORE SET ts_allpdb_saved_settings.sql REPLACE
SET TERMOUT ON

-- ---------- 2. Formatting for this report only ----------------
SET PAGESIZE 200
SET LINESIZE 190
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET TRIMOUT ON
SET TRIMSPOOL ON
SET TAB OFF
SET UNDERLINE =

-- Container and database name for the title
COLUMN con_name_col NEW_VALUE v_container NOPRINT
COLUMN db_name_col  NEW_VALUE v_dbname    NOPRINT
SELECT SYS_CONTEXT('USERENV', 'CON_NAME') AS con_name_col,
       SYS_CONTEXT('USERENV', 'DB_NAME')  AS db_name_col
FROM   dual;

-- Warn if not connected to CDB$ROOT
COLUMN warning FORMAT a100 HEADING ''
SELECT '*** WARNING: you are in container ' || SYS_CONTEXT('USERENV', 'CON_NAME') ||
       '. Run this script in CDB$ROOT to see all PDBs. ***' AS warning
FROM   dual
WHERE  SYS_CONTEXT('USERENV', 'CON_NAME') <> 'CDB$ROOT';

COLUMN container       FORMAT a16             HEADING 'Container'
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

BREAK ON container SKIP 1 ON REPORT
COMPUTE SUM LABEL 'Subtotal' OF size_mb used_mb free_mb max_mb ON container
COMPUTE SUM LABEL 'CDB total' OF size_mb used_mb free_mb max_mb ON report

TTITLE LEFT 'Tablespace usage: all containers   ' _DATE SKIP 1 -
       LEFT 'Database: ' v_dbname '   Connected to: ' v_container SKIP 1 -
       LEFT '==============================================================' SKIP 1

-- ---------- 3. Detail report: every tablespace, every container --
WITH df AS (
    SELECT con_id, tablespace_name,
           COUNT(*)                                   AS files,
           SUM(bytes)                                 AS bytes,
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes))) AS maxbytes,
           MAX(autoextensible)                        AS autoext
    FROM   cdb_data_files
    GROUP  BY con_id, tablespace_name
),
fs AS (
    SELECT con_id, tablespace_name, SUM(bytes) AS free_bytes
    FROM   cdb_free_space
    GROUP  BY con_id, tablespace_name
),
tf AS (
    SELECT con_id, tablespace_name,
           COUNT(*)                                   AS files,
           SUM(bytes)                                 AS bytes,
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes))) AS maxbytes,
           MAX(autoextensible)                        AS autoext
    FROM   cdb_temp_files
    GROUP  BY con_id, tablespace_name
),
usage AS (
    SELECT d.con_id, d.tablespace_name, t.contents, d.files, d.bytes, d.maxbytes, d.autoext,
           d.bytes - NVL(f.free_bytes, 0)             AS used_bytes
    FROM   df d
           JOIN cdb_tablespaces t ON t.con_id = d.con_id AND t.tablespace_name = d.tablespace_name
           LEFT JOIN fs f         ON f.con_id = d.con_id AND f.tablespace_name = d.tablespace_name
    UNION ALL
    SELECT x.con_id, x.tablespace_name, 'TEMPORARY', x.files, x.bytes, x.maxbytes, x.autoext,
           x.bytes - NVL(tfs.free_space, 0)
    FROM   tf x
           LEFT JOIN cdb_temp_free_space tfs
                  ON tfs.con_id = x.con_id AND tfs.tablespace_name = x.tablespace_name
)
SELECT c.name                                                AS container,
       u.tablespace_name,
       u.contents                                            AS ts_type,
       u.files,
       ROUND(u.bytes / 1048576, 1)                           AS size_mb,
       ROUND(u.used_bytes / 1048576, 1)                      AS used_mb,
       ROUND((u.bytes - u.used_bytes) / 1048576, 1)          AS free_mb,
       ROUND(100 * u.used_bytes / NULLIF(u.bytes, 0), 1)     AS pct_used,
       ROUND(u.maxbytes / 1048576, 1)                        AS max_mb,
       ROUND(100 * u.used_bytes / NULLIF(u.maxbytes, 0), 1)  AS pct_of_max,
       u.autoext,
       CASE
           WHEN u.contents = 'PERMANENT'
            AND 100 * u.used_bytes / NULLIF(u.maxbytes, 0) >= 90 THEN '<-- HIGH'
           WHEN u.contents = 'PERMANENT'
            AND 100 * u.used_bytes / NULLIF(u.maxbytes, 0) >= 80 THEN '<-- watch'
       END                                                   AS alert
FROM   usage u
       JOIN v$containers c ON c.con_id = u.con_id
ORDER  BY u.con_id, pct_of_max DESC NULLS LAST, u.tablespace_name;

-- ---------- 4. Summary: one line per container -----------------
CLEAR BREAKS
CLEAR COMPUTES
TTITLE OFF

COLUMN open_mode   FORMAT a10   HEADING 'Open mode'
COLUMN ts_count    FORMAT 990   HEADING 'TS'
COLUMN high_count  FORMAT 990   HEADING '>=80% Max'

BREAK ON REPORT
COMPUTE SUM LABEL 'CDB total' OF size_mb used_mb free_mb ON report

PROMPT
PROMPT Summary by container (permanent, undo and temp combined)
PROMPT ========================================================
WITH df AS (
    SELECT con_id, tablespace_name, SUM(bytes) AS bytes,
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes))) AS maxbytes
    FROM   cdb_data_files GROUP BY con_id, tablespace_name
    UNION ALL
    SELECT con_id, tablespace_name, SUM(bytes),
           SUM(GREATEST(bytes, DECODE(autoextensible, 'YES', maxbytes, bytes)))
    FROM   cdb_temp_files GROUP BY con_id, tablespace_name
),
fs AS (
    SELECT con_id, tablespace_name, SUM(bytes) AS free_bytes
    FROM   cdb_free_space GROUP BY con_id, tablespace_name
    UNION ALL
    SELECT con_id, tablespace_name, free_space
    FROM   cdb_temp_free_space
),
per_ts AS (
    SELECT d.con_id, d.tablespace_name, d.bytes, d.maxbytes,
           d.bytes - NVL(f.free_bytes, 0) AS used_bytes
    FROM   df d
           LEFT JOIN fs f ON f.con_id = d.con_id AND f.tablespace_name = d.tablespace_name
)
SELECT c.name                                                AS container,
       c.open_mode,
       COUNT(*)                                              AS ts_count,
       ROUND(SUM(p.bytes) / 1048576, 1)                      AS size_mb,
       ROUND(SUM(p.used_bytes) / 1048576, 1)                 AS used_mb,
       ROUND(SUM(p.bytes - p.used_bytes) / 1048576, 1)       AS free_mb,
       ROUND(100 * SUM(p.used_bytes) / NULLIF(SUM(p.bytes), 0), 1) AS pct_used,
       SUM(CASE WHEN 100 * p.used_bytes / NULLIF(p.maxbytes, 0) >= 80 THEN 1 ELSE 0 END) AS high_count
FROM   per_ts p
       JOIN v$containers c ON c.con_id = p.con_id
GROUP  BY p.con_id, c.name, c.open_mode
ORDER  BY p.con_id;

-- ---------- 5. Containers that could not be read ---------------
CLEAR BREAKS
CLEAR COMPUTES
COLUMN name FORMAT a30 HEADING 'Container not reported'
PROMPT
PROMPT PDBs not open (their tablespaces cannot be read until opened):
SELECT name, open_mode
FROM   v$containers
WHERE  open_mode NOT IN ('READ WRITE', 'READ ONLY')
  AND  name <> 'PDB$SEED'
ORDER  BY con_id;

PROMPT
PROMPT Notes: UNDO and TEMP space is reused automatically, so high usage there is often normal.
PROMPT        Watch "% of Max" for PERMANENT tablespaces: 80% = plan to add space, 90% = act now.
PROMPT

-- ---------- 6. Undo the formatting -----------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_container v_dbname

SET TERMOUT OFF
@ts_allpdb_saved_settings.sql
SET TERMOUT ON

-- Remove the temporary settings file
-- (Linux/Unix; on Windows change "rm -f" to "del")
HOST rm -f ts_allpdb_saved_settings.sql
