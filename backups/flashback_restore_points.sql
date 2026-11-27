-- =============================================================
-- Script   : flashback_restore_points.sql
-- Purpose  : Flashback Database status, how far back you can flash back,
--            flashback log space, and restore points (guaranteed ones
--            hold flashback logs and can fill the FRA)
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT to see CDB and PDB restore points.
--            Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @flashback_restore_points.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET flashback_restore_points_saved_settings.sql REPLACE
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
TTITLE LEFT 'Flashback and restore points   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN flashback_on    FORMAT a18 HEADING 'Flashback on'
COLUMN log_mode        FORMAT a12 HEADING 'Log mode'
COLUMN target_min      FORMAT 99,990 HEADING 'Target min'
COLUMN oldest_fb       FORMAT a17 HEADING 'Oldest flashback'
COLUMN hours_back      FORMAT 9,990.9 HEADING 'Hours back'
COLUMN fb_gb           FORMAT 99,990.9 HEADING 'FB logs GB'
COLUMN est_gb          FORMAT 99,990.9 HEADING 'Est. need GB'

PROMPT
PROMPT Flashback Database status and window
SELECT d.flashback_on,
       d.log_mode,
       TO_NUMBER(p.value)                                      AS target_min,
       TO_CHAR(f.oldest_flashback_time, 'DD-MON-YY HH24:MI')   AS oldest_fb,
       ROUND((SYSDATE - f.oldest_flashback_time) * 24, 1)      AS hours_back,
       ROUND(f.flashback_size / POWER(1024,3), 1)              AS fb_gb,
       ROUND(f.estimated_flashback_size / POWER(1024,3), 1)    AS est_gb
FROM   v$database d
       JOIN v$parameter p ON p.name = 'db_flashback_retention_target'
       LEFT JOIN v$flashback_database_log f ON 1 = 1;

COLUMN container FORMAT a14 HEADING 'Container'
COLUMN rp_name   FORMAT a30 HEADING 'Restore point'
COLUMN guar      FORMAT a5  HEADING 'Guar.'
COLUMN created   FORMAT a17 HEADING 'Created'
COLUMN age_days  FORMAT 9,990.9 HEADING 'Days old'
COLUMN gb        FORMAT 99,990.9 HEADING 'GB held'
COLUMN flag      FORMAT a22 HEADING 'Check'
PROMPT
PROMPT Restore points (oldest first)
SELECT NVL(c.name, 'NON-CDB / CDB')                         AS container,
       r.name                                               AS rp_name,
       r.guarantee_flashback_database                       AS guar,
       TO_CHAR(r.time, 'DD-MON-YY HH24:MI')                 AS created,
       ROUND(SYSDATE - CAST(r.time AS DATE), 1)             AS age_days,
       ROUND(r.storage_size / POWER(1024,3), 1)             AS gb,
       CASE WHEN r.guarantee_flashback_database = 'YES'
             AND SYSDATE - CAST(r.time AS DATE) > 7 THEN '<-- old guaranteed RP' END AS flag
FROM   v$restore_point r
       LEFT JOIN v$containers c ON c.con_id = r.con_id AND r.con_id > 1
ORDER  BY r.time;

COLUMN pct_used FORMAT 990.0 HEADING '% of FRA'
PROMPT
PROMPT Fast Recovery Area space used by flashback logs
SELECT file_type, percent_space_used AS pct_used, number_of_files
FROM   v$recovery_area_usage
WHERE  file_type = 'FLASHBACK LOG';

PROMPT
PROMPT Guaranteed restore points keep every flashback log since they were made, so old ones can fill
PROMPT the FRA and stop the database. Drop one you no longer need with:
PROMPT   DROP RESTORE POINT <name>;   (in a PDB for PDB restore points)
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con 
SET TERMOUT OFF
@flashback_restore_points_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f flashback_restore_points_saved_settings.sql
