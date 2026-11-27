-- =============================================================
-- Script   : archivelog_generation.sql
-- Purpose  : Archived redo generated per day and per hour (heat map),
--            plus archive logs on disk that have never been backed up
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : Any container. Archive logs belong to the whole CDB,
--            so the result is the same from the root or a PDB.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @archivelog_generation.sql
-- Settings : "days_back" = days to report (hour map shows the
--            last 7 days at most).
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 14
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET archivelog_generation_saved_settings.sql REPLACE
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
TTITLE LEFT 'Archive log generation   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

-- Each log can be archived to several destinations; count it once
-- (by thread, sequence and incarnation) using local destinations only.
COLUMN day     FORMAT a11       HEADING 'Day'
COLUMN logs    FORMAT 99,990    HEADING 'Logs'
COLUMN gb      FORMAT 99,990.9  HEADING 'GB'
COLUMN avg_mb  FORMAT 99,990    HEADING 'Avg MB'
COLUMN thread# FORMAT 990       HEADING 'Thread'

PROMPT
PROMPT Archived redo per day, last &days_back days
SELECT TO_CHAR(TRUNC(first_time), 'DD-MON-YY')       AS day,
       COUNT(*)                                       AS logs,
       ROUND(SUM(bytes) / POWER(1024,3), 1)           AS gb,
       ROUND(AVG(bytes) / POWER(1024,2))              AS avg_mb
FROM  (SELECT thread#, sequence#, resetlogs_change#,
              MIN(first_time) first_time, MAX(blocks * block_size) bytes
       FROM   v$archived_log
       WHERE  standby_dest = 'NO'
       AND    first_time > TRUNC(SYSDATE) - &days_back
       GROUP  BY thread#, sequence#, resetlogs_change#)
GROUP  BY TRUNC(first_time)
ORDER  BY TRUNC(first_time) DESC;

SET LINESIZE 220
COLUMN h00 FORMAT 999 HEADING '00'
COLUMN h01 FORMAT 999 HEADING '01'
COLUMN h02 FORMAT 999 HEADING '02'
COLUMN h03 FORMAT 999 HEADING '03'
COLUMN h04 FORMAT 999 HEADING '04'
COLUMN h05 FORMAT 999 HEADING '05'
COLUMN h06 FORMAT 999 HEADING '06'
COLUMN h07 FORMAT 999 HEADING '07'
COLUMN h08 FORMAT 999 HEADING '08'
COLUMN h09 FORMAT 999 HEADING '09'
COLUMN h10 FORMAT 999 HEADING '10'
COLUMN h11 FORMAT 999 HEADING '11'
COLUMN h12 FORMAT 999 HEADING '12'
COLUMN h13 FORMAT 999 HEADING '13'
COLUMN h14 FORMAT 999 HEADING '14'
COLUMN h15 FORMAT 999 HEADING '15'
COLUMN h16 FORMAT 999 HEADING '16'
COLUMN h17 FORMAT 999 HEADING '17'
COLUMN h18 FORMAT 999 HEADING '18'
COLUMN h19 FORMAT 999 HEADING '19'
COLUMN h20 FORMAT 999 HEADING '20'
COLUMN h21 FORMAT 999 HEADING '21'
COLUMN h22 FORMAT 999 HEADING '22'
COLUMN h23 FORMAT 999 HEADING '23'
PROMPT
PROMPT Log switches per hour, last 7 days (all threads). Over ~12 an hour usually means redo logs are too small.
SELECT TO_CHAR(TRUNC(first_time), 'DD-MON-YY') AS day,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'00',1,0)) h00, SUM(DECODE(TO_CHAR(first_time,'HH24'),'01',1,0)) h01,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'02',1,0)) h02, SUM(DECODE(TO_CHAR(first_time,'HH24'),'03',1,0)) h03,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'04',1,0)) h04, SUM(DECODE(TO_CHAR(first_time,'HH24'),'05',1,0)) h05,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'06',1,0)) h06, SUM(DECODE(TO_CHAR(first_time,'HH24'),'07',1,0)) h07,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'08',1,0)) h08, SUM(DECODE(TO_CHAR(first_time,'HH24'),'09',1,0)) h09,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'10',1,0)) h10, SUM(DECODE(TO_CHAR(first_time,'HH24'),'11',1,0)) h11,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'12',1,0)) h12, SUM(DECODE(TO_CHAR(first_time,'HH24'),'13',1,0)) h13,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'14',1,0)) h14, SUM(DECODE(TO_CHAR(first_time,'HH24'),'15',1,0)) h15,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'16',1,0)) h16, SUM(DECODE(TO_CHAR(first_time,'HH24'),'17',1,0)) h17,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'18',1,0)) h18, SUM(DECODE(TO_CHAR(first_time,'HH24'),'19',1,0)) h19,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'20',1,0)) h20, SUM(DECODE(TO_CHAR(first_time,'HH24'),'21',1,0)) h21,
       SUM(DECODE(TO_CHAR(first_time,'HH24'),'22',1,0)) h22, SUM(DECODE(TO_CHAR(first_time,'HH24'),'23',1,0)) h23
FROM   v$log_history
WHERE  first_time > TRUNC(SYSDATE) - LEAST(&days_back, 7)
GROUP  BY TRUNC(first_time)
ORDER  BY TRUNC(first_time) DESC;
SET LINESIZE 200

COLUMN oldest FORMAT a17 HEADING 'Oldest not backed up'
PROMPT
PROMPT Archive logs on disk that have NEVER been backed up, per thread
SELECT thread#,
       COUNT(*)                                        AS logs,
       ROUND(SUM(blocks * block_size) / POWER(1024,3), 1) AS gb,
       TO_CHAR(MIN(first_time), 'DD-MON-YY HH24:MI')   AS oldest
FROM   v$archived_log
WHERE  standby_dest = 'NO'
AND    deleted = 'NO'
AND    status = 'A'
AND    backup_count = 0
GROUP  BY thread#
ORDER  BY thread#;

PROMPT
PROMPT Many unbacked-up logs, or an old "oldest" time, means archive log backups are not running.
PROMPT Check: backups/rman_backup_status.sql and Fast Recovery Area use in backups/backup_coverage_fra.sql
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@archivelog_generation_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f archivelog_generation_saved_settings.sql
