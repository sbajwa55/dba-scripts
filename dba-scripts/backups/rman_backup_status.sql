-- =============================================================
-- Script   : rman_backup_status.sql
-- Purpose  : RMAN backup jobs for the last N days, plus the last
--            successful backup of each type with an age check
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT (RMAN backs up the whole CDB, so
--            job history is held in the root). Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @rman_backup_status.sql
-- Settings : Change "days_back" below to look further back.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 7
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET rman_backup_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'RMAN backup status   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN start_time   FORMAT a17  HEADING 'Started'
COLUMN end_time     FORMAT a17  HEADING 'Finished'
COLUMN input_type   FORMAT a13  HEADING 'Type'
COLUMN status       FORMAT a24  HEADING 'Status'
COLUMN in_size      FORMAT a10  HEADING 'Input'
COLUMN out_size     FORMAT a10  HEADING 'Output'
COLUMN duration     FORMAT a10  HEADING 'Duration'
COLUMN device       FORMAT a10  HEADING 'Device'
COLUMN flag         FORMAT a12  HEADING 'Check'

PROMPT
PROMPT RMAN jobs in the last &days_back days (newest first)
SELECT TO_CHAR(start_time, 'DD-MON-YY HH24:MI') AS start_time,
       TO_CHAR(end_time,   'DD-MON-YY HH24:MI') AS end_time,
       input_type,
       status,
       TRIM(input_bytes_display)  AS in_size,
       TRIM(output_bytes_display) AS out_size,
       TRIM(time_taken_display)   AS duration,
       output_device_type         AS device,
       CASE WHEN status LIKE '%FAILED%' OR status LIKE '%ERROR%' THEN '<-- FAILED'
            WHEN status LIKE '%WARNING%'                         THEN '<-- warning'
            WHEN status = 'RUNNING'                              THEN 'running' END AS flag
FROM   v$rman_backup_job_details
WHERE  start_time > SYSDATE - &days_back
ORDER  BY start_time DESC;

COLUMN last_ok   FORMAT a17  HEADING 'Last successful'
COLUMN age_hours FORMAT 99,990.9 HEADING 'Hours ago'
PROMPT
PROMPT Last successful backup of each type
SELECT input_type,
       TO_CHAR(MAX(end_time), 'DD-MON-YY HH24:MI')        AS last_ok,
       ROUND((SYSDATE - MAX(end_time)) * 24, 1)           AS age_hours,
       CASE
         WHEN input_type = 'ARCHIVELOG'      AND (SYSDATE - MAX(end_time)) * 24 > 24  THEN '<-- over 24h'
         WHEN input_type IN ('DB FULL','DB INCR') AND SYSDATE - MAX(end_time) > 7     THEN '<-- over 7d'
       END                                                AS flag
FROM   v$rman_backup_job_details
WHERE  status IN ('COMPLETED', 'COMPLETED WITH WARNINGS')
GROUP  BY input_type
ORDER  BY input_type;

PROMPT
PROMPT No rows above = no RMAN backups recorded in the control file for this period.
PROMPT If you use an RMAN recovery catalog, history older than CONTROL_FILE_RECORD_KEEP_TIME is in the catalog.
PROMPT
-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@rman_backup_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f rman_backup_status_saved_settings.sql

