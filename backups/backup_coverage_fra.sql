-- =============================================================
-- Script   : backup_coverage_fra.sql
-- Purpose  : Datafiles with no recent backup, Fast Recovery Area
--            (FRA) usage, and non-default RMAN configuration
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see the datafiles of the root
--            and every PDB. Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @backup_coverage_fra.sql
-- Settings : "stale_days" = flag datafiles not backed up in N days.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE stale_days = 2
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET backup_coverage_fra_saved_settings.sql REPLACE
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
TTITLE LEFT 'Backup coverage and FRA   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN container   FORMAT a14  HEADING 'Container'
COLUMN file#       FORMAT 9990 HEADING 'File#'
COLUMN file_name   FORMAT a60  HEADING 'Datafile'
COLUMN last_backup FORMAT a17  HEADING 'Last backup'
COLUMN age_days    FORMAT 9,990.9 HEADING 'Days ago'

PROMPT
PROMPT Datafiles not backed up in the last &stale_days days (or never)
SELECT NVL(c.name, 'NON-CDB')                              AS container,
       d.file#,
       d.name                                              AS file_name,
       NVL(TO_CHAR(b.last_bkp, 'DD-MON-YY HH24:MI'), 'NEVER') AS last_backup,
       ROUND(SYSDATE - b.last_bkp, 1)                      AS age_days
FROM   v$datafile d
       LEFT JOIN (SELECT file#, MAX(completion_time) last_bkp
                  FROM   v$backup_datafile
                  GROUP  BY file#) b ON b.file# = d.file#
       LEFT JOIN v$containers c ON c.con_id = d.con_id
WHERE  b.last_bkp IS NULL OR b.last_bkp < SYSDATE - &stale_days
ORDER  BY d.con_id, d.file#;

COLUMN name        FORMAT a30         HEADING 'FRA location'
COLUMN limit_gb    FORMAT 999,990.9   HEADING 'Limit GB'
COLUMN used_gb     FORMAT 999,990.9   HEADING 'Used GB'
COLUMN reclaim_gb  FORMAT 999,990.9   HEADING 'Reclaimable GB'
COLUMN pct_used    FORMAT 990.9       HEADING 'Used %'
COLUMN files       FORMAT 999,990     HEADING 'Files'
COLUMN fra_flag    FORMAT a12         HEADING 'Check'
PROMPT
PROMPT Fast Recovery Area
SELECT name,
       ROUND(space_limit / 1073741824, 1)                  AS limit_gb,
       ROUND(space_used / 1073741824, 1)                   AS used_gb,
       ROUND(space_reclaimable / 1073741824, 1)            AS reclaim_gb,
       ROUND(100 * (space_used - space_reclaimable) / NULLIF(space_limit, 0), 1) AS pct_used,
       number_of_files                                     AS files,
       CASE WHEN 100 * (space_used - space_reclaimable) / NULLIF(space_limit, 0) >= 85
            THEN '<-- HIGH' END                            AS fra_flag
FROM   v$recovery_file_dest;

COLUMN file_type FORMAT a24   HEADING 'File type'
COLUMN pct_space FORMAT 990.9 HEADING 'Used %'
COLUMN pct_recl  FORMAT 990.9 HEADING 'Reclaimable %'
COLUMN nfiles    FORMAT 999,990 HEADING 'Files'
SELECT file_type, percent_space_used AS pct_space, percent_space_reclaimable AS pct_recl, number_of_files AS nfiles
FROM   v$recovery_area_usage
WHERE  number_of_files > 0
ORDER  BY percent_space_used DESC;

COLUMN cfg_name  FORMAT a40 HEADING 'RMAN setting (non-default)'
COLUMN cfg_value FORMAT a80 HEADING 'Value'
PROMPT
PROMPT RMAN configuration changed from default (empty = all defaults)
SELECT name AS cfg_name, value AS cfg_value FROM v$rman_configuration ORDER BY conf#;
PROMPT
PROMPT Tip: "Used %" for the FRA excludes reclaimable space. Over 85% risks the database halting on archiver errors.
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@backup_coverage_fra_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f backup_coverage_fra_saved_settings.sql

