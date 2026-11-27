-- =============================================================
-- Script   : backup_size_trend.sql
-- Purpose  : Daily RMAN backup volume for the last N days: data read,
--            backup written, compression ratio and run time by type
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB: run in CDB$ROOT (backups cover the whole CDB, so
--            RMAN history is held in the root). Non-CDB: run normally.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @backup_size_trend.sql
-- Settings : "days_back" = how many days to report.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 30
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET backup_size_trend_saved_settings.sql REPLACE
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
TTITLE LEFT 'Backup size trend   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN day        FORMAT a11       HEADING 'Day'
COLUMN input_type FORMAT a13       HEADING 'Type'
COLUMN jobs       FORMAT 990       HEADING 'Jobs'
COLUMN in_gb      FORMAT 999,990.9 HEADING 'Read GB'
COLUMN out_gb     FORMAT 999,990.9 HEADING 'Written GB'
COLUMN ratio      FORMAT 990.0     HEADING 'Ratio'
COLUMN hours      FORMAT 990.0     HEADING 'Hours'
COLUMN mb_sec     FORMAT 99,990    HEADING 'MB/s'
BREAK ON day SKIP 1

PROMPT
PROMPT Backup volume per day and type, last &days_back days (completed jobs)
SELECT TO_CHAR(TRUNC(start_time), 'DD-MON-YY')                       AS day,
       input_type,
       COUNT(*)                                                      AS jobs,
       ROUND(SUM(input_bytes)  / POWER(1024,3), 1)                   AS in_gb,
       ROUND(SUM(output_bytes) / POWER(1024,3), 1)                   AS out_gb,
       ROUND(SUM(input_bytes) / NULLIF(SUM(output_bytes), 0), 1)     AS ratio,
       ROUND(SUM(elapsed_seconds) / 3600, 1)                         AS hours,
       ROUND(SUM(input_bytes) / NULLIF(SUM(elapsed_seconds), 0) / POWER(1024,2)) AS mb_sec
FROM   v$rman_backup_job_details
WHERE  start_time > TRUNC(SYSDATE) - &days_back
AND    status LIKE 'COMPLETED%'
GROUP  BY TRUNC(start_time), input_type
ORDER  BY TRUNC(start_time) DESC, input_type;
CLEAR BREAKS

PROMPT
PROMPT Average per job by type over the same period
SELECT input_type,
       COUNT(*)                                                      AS jobs,
       ROUND(AVG(input_bytes)  / POWER(1024,3), 1)                   AS in_gb,
       ROUND(AVG(output_bytes) / POWER(1024,3), 1)                   AS out_gb,
       ROUND(SUM(input_bytes) / NULLIF(SUM(output_bytes), 0), 1)     AS ratio,
       ROUND(AVG(elapsed_seconds) / 3600, 1)                         AS hours,
       ROUND(SUM(input_bytes) / NULLIF(SUM(elapsed_seconds), 0) / POWER(1024,2)) AS mb_sec
FROM   v$rman_backup_job_details
WHERE  start_time > TRUNC(SYSDATE) - &days_back
AND    status LIKE 'COMPLETED%'
GROUP  BY input_type
ORDER  BY input_type;

PROMPT
PROMPT Ratio = data read / backup written. Above 1 means compression or unused-block skipping is working.
PROMPT A falling MB/s with steady volume points to slower storage, network or media manager.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@backup_size_trend_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f backup_size_trend_saved_settings.sql
