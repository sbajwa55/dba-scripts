-- =============================================================
-- Script   : scheduler_jobs_status.sql
-- Purpose  : DBMS_SCHEDULER health: jobs that failed in the last N days
--            with the error, jobs running now and for how long, broken
--            or disabled application jobs, and the autotask windows
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB you want to check (or a non-CDB). Run it in each
--            PDB; CDB$ROOT shows the root only.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @scheduler_jobs_status.sql
-- Settings : "days_back" = failures to show.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 3
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET scheduler_jobs_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'Scheduler jobs   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN job       FORMAT a44 HEADING 'Job'
COLUMN started   FORMAT a15 HEADING 'Started'
COLUMN status    FORMAT a10 HEADING 'Status'
COLUMN error#    FORMAT 99990 HEADING 'Error'
COLUMN info      FORMAT a60 HEADING 'Message' WORD_WRAPPED
PROMPT
PROMPT Failed or stopped job runs in the last &days_back days (newest first)
SELECT owner || '.' || job_name AS job,
       TO_CHAR(actual_start_date, 'DD-MON HH24:MI') AS started,
       status, error#,
       SUBSTR(REPLACE(additional_info, CHR(10), ' '), 1, 180) AS info
FROM   dba_scheduler_job_run_details
WHERE  log_date > SYSTIMESTAMP - NUMTODSINTERVAL(&days_back, 'DAY')
AND    status <> 'SUCCEEDED'
ORDER  BY log_date DESC
FETCH FIRST 40 ROWS ONLY;

COLUMN runs     FORMAT 9,990 HEADING 'Runs'
COLUMN fails    FORMAT 9,990 HEADING 'Failed'
PROMPT
PROMPT Runs and failures per job, last &days_back days
SELECT owner || '.' || job_name AS job, COUNT(*) AS runs,
       SUM(CASE WHEN status <> 'SUCCEEDED' THEN 1 ELSE 0 END) AS fails
FROM   dba_scheduler_job_run_details
WHERE  log_date > SYSTIMESTAMP - NUMTODSINTERVAL(&days_back, 'DAY')
GROUP  BY owner, job_name
HAVING SUM(CASE WHEN status <> 'SUCCEEDED' THEN 1 ELSE 0 END) > 0
ORDER  BY fails DESC;

COLUMN elapsed FORMAT a20 HEADING 'Running for'
COLUMN sess    FORMAT a12 HEADING 'Inst:SID'
PROMPT
PROMPT Jobs running now
SELECT owner || '.' || job_name AS job,
       running_instance || ':' || session_id AS sess,
       TO_CHAR(elapsed_time) AS elapsed
FROM   dba_scheduler_running_jobs
ORDER  BY elapsed_time DESC;

COLUMN state     FORMAT a10 HEADING 'State'
COLUMN failures  FORMAT 9,990 HEADING 'Failures'
COLUMN next_run  FORMAT a15 HEADING 'Next run'
PROMPT
PROMPT Application jobs that are broken, disabled, or keep failing
SELECT j.owner || '.' || j.job_name AS job, j.state, j.failure_count AS failures,
       TO_CHAR(j.next_run_date, 'DD-MON HH24:MI') AS next_run
FROM   dba_scheduler_jobs j JOIN dba_users u ON u.username = j.owner
WHERE  u.oracle_maintained = 'N'
AND   (j.state IN ('BROKEN', 'DISABLED', 'FAILED') OR j.failure_count > 0)
ORDER  BY j.failure_count DESC;

COLUMN window_name FORMAT a20 HEADING 'Maintenance window'
COLUMN enabled     FORMAT a7  HEADING 'Enabled'
COLUMN next_start  FORMAT a17 HEADING 'Next start'
COLUMN duration    FORMAT a14 HEADING 'Duration'
PROMPT
PROMPT Maintenance windows (stats gathering, segment advisor, ...)
SELECT window_name, enabled, TO_CHAR(next_start_date, 'DD-MON-YY HH24:MI') AS next_start,
       TO_CHAR(duration) AS duration
FROM   dba_scheduler_windows
ORDER  BY next_start_date;

PROMPT
PROMPT Old-style DBMS_JOB jobs are converted to scheduler jobs in 19c and show up here too.
PROMPT Re-run a job now:  EXEC DBMS_SCHEDULER.RUN_JOB('<owner>.<job_name>', use_current_session => FALSE);
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@scheduler_jobs_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f scheduler_jobs_status_saved_settings.sql
