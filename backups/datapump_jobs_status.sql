-- =============================================================
-- Script   : datapump_jobs_status.sql
-- Purpose  : Data Pump export and import jobs: running jobs, progress,
--            attached sessions, and stopped or orphaned jobs to clean up
-- Section  : Backups
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The container where the jobs run (Data Pump jobs belong
--            to a PDB): ALTER SESSION SET CONTAINER = <PDB_NAME>;
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @datapump_jobs_status.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET datapump_jobs_status_saved_settings.sql REPLACE
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
TTITLE LEFT 'Data Pump jobs   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN owner_name FORMAT a14 HEADING 'Owner'
COLUMN job_name   FORMAT a28 HEADING 'Job'
COLUMN operation  FORMAT a8  HEADING 'Op'
COLUMN job_mode   FORMAT a10 HEADING 'Mode'
COLUMN state      FORMAT a20 HEADING 'State'
COLUMN degree     FORMAT 990 HEADING 'DOP'
COLUMN attached   FORMAT 990 HEADING 'Attached'
COLUMN flag       FORMAT a24 HEADING 'Check'

PROMPT
PROMPT All Data Pump jobs known to this container
SELECT owner_name, job_name, operation, job_mode, state, degree,
       attached_sessions AS attached,
       CASE WHEN state = 'NOT RUNNING' AND attached_sessions = 0
            THEN '<-- stopped or orphaned' END AS flag
FROM   dba_datapump_jobs
ORDER  BY state, owner_name, job_name;

COLUMN opname    FORMAT a28      HEADING 'Job'
COLUMN pct_done  FORMAT 990.0    HEADING '% done'
COLUMN sofar_mb  FORMAT 9,999,990 HEADING 'MB done'
COLUMN total_mb  FORMAT 9,999,990 HEADING 'MB est.'
COLUMN started   FORMAT a17      HEADING 'Started'
COLUMN left_min  FORMAT 99,990   HEADING 'Min left'
PROMPT
PROMPT Progress of running jobs (estimate from V$SESSION_LONGOPS)
SELECT l.opname,
       ROUND(l.sofar / NULLIF(l.totalwork, 0) * 100, 1)   AS pct_done,
       l.sofar      AS sofar_mb,
       l.totalwork  AS total_mb,
       TO_CHAR(l.start_time, 'DD-MON-YY HH24:MI')        AS started,
       ROUND(l.time_remaining / 60)                       AS left_min
FROM   gv$session_longops l
       JOIN dba_datapump_jobs j ON j.job_name = l.opname AND j.owner_name = l.username
WHERE  l.sofar < l.totalwork
ORDER  BY l.start_time;

COLUMN inst_id      FORMAT 990    HEADING 'Inst'
COLUMN sid          FORMAT 99990  HEADING 'SID'
COLUMN session_type FORMAT a14    HEADING 'Role'
COLUMN event        FORMAT a40    HEADING 'Waiting on'
PROMPT
PROMPT Sessions working for each job (master, workers, client)
SELECT d.job_name, s.inst_id, s.sid, d.session_type, s.event
FROM   dba_datapump_sessions d
       JOIN gv$session s ON s.saddr = d.saddr
ORDER  BY d.job_name, d.session_type, s.inst_id, s.sid;

COLUMN master_table FORMAT a45 HEADING 'Master table left behind'
PROMPT
PROMPT Possible orphaned master tables (job not running, table still present)
SELECT o.owner || '.' || o.object_name AS master_table,
       TO_CHAR(o.created, 'DD-MON-YY HH24:MI') AS started
FROM   dba_objects o
       JOIN dba_datapump_jobs j ON j.owner_name = o.owner AND j.job_name = o.object_name
WHERE  o.object_type = 'TABLE'
AND    j.state = 'NOT RUNNING'
AND    j.attached_sessions = 0
ORDER  BY o.created;

PROMPT
PROMPT Attach to a job:  expdp <user> ATTACH=<JOB_NAME>   then STATUS, STOP_JOB or KILL_JOB
PROMPT Orphaned job: if you do not need to restart it, KILL_JOB from ATTACH, or drop the master
PROMPT table above (DROP TABLE <owner>.<job_name> PURGE;) only after confirming it is not in use.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con 
SET TERMOUT OFF
@datapump_jobs_status_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f datapump_jobs_status_saved_settings.sql
