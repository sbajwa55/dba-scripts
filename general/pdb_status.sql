-- =============================================================
-- Script   : pdb_status.sql
-- Purpose  : List all PDBs with their current open mode
--            (READ WRITE, READ ONLY, MOUNTED, MIGRATE), restricted
--            flag, open time, size and saved startup state
-- Section  : General
-- Database : Oracle 12c, 19c, 21c (multitenant / CDB only)
-- Run as   : SYSTEM (or SYS) connected to CDB$ROOT
-- Changes  : None (read-only)
-- Client   : SQL*Plus
-- Usage    : SQL> ALTER SESSION SET CONTAINER = CDB$ROOT;
--            SQL> @pdb_status.sql
-- Where    : Run it in CDB$ROOT. Inside a PDB it shows only that PDB.
-- Notes    : "Saved state" shows whether the PDB reopens automatically
--            when the CDB restarts (set with ALTER PLUGGABLE DATABASE
--            <name> SAVE STATE). Blank means it stays MOUNTED after a
--            restart. Your SQL*Plus settings are restored at the end.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================

SET TERMOUT OFF
STORE SET pdb_status_saved_settings.sql REPLACE
SET TERMOUT ON

SET PAGESIZE 100
SET LINESIZE 150
SET FEEDBACK OFF
SET VERIFY OFF
SET TRIMOUT ON
SET TAB OFF
SET UNDERLINE =

COLUMN con_id       FORMAT 990            HEADING 'Con ID'
COLUMN pdb_name     FORMAT a20            HEADING 'PDB'
COLUMN open_mode    FORMAT a10            HEADING 'Open mode'
COLUMN restricted   FORMAT a10            HEADING 'Restricted'
COLUMN open_time    FORMAT a20            HEADING 'Opened at'
COLUMN size_gb      FORMAT 999,990.99     HEADING 'Size GB'
COLUMN pdb_status   FORMAT a10            HEADING 'Status'
COLUMN saved_state  FORMAT a11            HEADING 'Saved state'
COLUMN check_flag   FORMAT a16            HEADING 'Check'

PROMPT
SELECT 'Database: ' || SYS_CONTEXT('USERENV', 'DB_NAME') ||
       '    Connected to: ' || SYS_CONTEXT('USERENV', 'CON_NAME') ||
       '    ' || TO_CHAR(SYSDATE, 'DD-MON-YYYY HH24:MI') AS " "
FROM   dual;

SELECT p.con_id,
       p.name                                         AS pdb_name,
       p.open_mode,
       NVL(p.restricted, '-')                         AS restricted,
       NVL(TO_CHAR(CAST(p.open_time AS DATE), 'DD-MON-YYYY HH24:MI'), '-') AS open_time,
       ROUND(p.total_size / 1073741824, 2)            AS size_gb,
       c.status                                       AS pdb_status,
       NVL(s.state, '-')                              AS saved_state,
       CASE
           WHEN p.name = 'PDB$SEED'                THEN NULL
           WHEN p.open_mode = 'MOUNTED'            THEN '<-- not open'
           WHEN p.restricted = 'YES'               THEN '<-- restricted'
           WHEN p.open_mode = 'MIGRATE'            THEN '<-- upgrade mode'
       END                                            AS check_flag
FROM   v$pdbs p
       LEFT JOIN cdb_pdbs c              ON c.con_id   = p.con_id
       LEFT JOIN dba_pdb_saved_states s  ON s.con_name = p.name
ORDER  BY p.con_id;

PROMPT
PROMPT PDB$SEED is always READ ONLY; that is normal.
PROMPT To open a mounted PDB:  ALTER PLUGGABLE DATABASE <name> OPEN;
PROMPT To keep it open after a CDB restart:  ALTER PLUGGABLE DATABASE <name> SAVE STATE;
PROMPT

CLEAR COLUMNS
SET TERMOUT OFF
@pdb_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f pdb_status_saved_settings.sql
