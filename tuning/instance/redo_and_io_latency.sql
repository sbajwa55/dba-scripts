-- =============================================================
-- Script   : redo_and_io_latency.sql
-- Purpose  : Storage response times: average read/write time per
--            tablespace and datafile, redo log size and switch rate,
--            and commit latency (log file sync)
-- Section  : Tuning / Instance
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB, on each RAC instance (figures are
--            per instance, cumulative since startup).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @redo_and_io_latency.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET redo_and_io_latency_saved_settings.sql REPLACE
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
TTITLE LEFT 'Redo and I/O latency   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN event     FORMAT a32         HEADING 'Event'
COLUMN waits     FORMAT 999,999,999,990 HEADING 'Waits'
COLUMN avg_ms    FORMAT 9,990.00    HEADING 'Avg ms'
COLUMN guide     FORMAT a32         HEADING 'Typical healthy value'
PROMPT
PROMPT Key I/O and commit waits since startup
SELECT event, total_waits AS waits,
       ROUND(time_waited_micro / NULLIF(total_waits, 0) / 1000, 2) AS avg_ms,
       CASE event
         WHEN 'db file sequential read'  THEN 'SSD < 1 ms, disk < 10 ms'
         WHEN 'db file scattered read'   THEN 'under 20 ms'
         WHEN 'log file sync'            THEN 'under 5 ms (commit time)'
         WHEN 'log file parallel write'  THEN 'under 2-3 ms'
         WHEN 'db file parallel write'   THEN 'background, usually ok'
         WHEN 'direct path read'         THEN 'under 20 ms'
         WHEN 'cell single block physical read' THEN 'Exadata: under 1 ms'
       END AS guide
FROM   v$system_event
WHERE  event IN ('db file sequential read', 'db file scattered read', 'log file sync',
                 'log file parallel write', 'db file parallel write', 'direct path read',
                 'direct path write temp', 'cell single block physical read', 'cell smart table scan')
ORDER  BY time_waited_micro DESC;

COLUMN tablespace FORMAT a24       HEADING 'Tablespace'
COLUMN reads      FORMAT 999,999,999,990 HEADING 'Reads'
COLUMN rd_ms      FORMAT 9,990.00  HEADING 'Avg read ms'
COLUMN writes     FORMAT 999,999,999,990 HEADING 'Writes'
COLUMN wr_ms      FORMAT 9,990.00  HEADING 'Avg write ms'
PROMPT
PROMPT Read and write time per tablespace (READTIM/WRITETIM are in centiseconds)
SELECT t.name AS tablespace,
       SUM(f.phyrds)  AS reads,
       ROUND(SUM(f.readtim)  * 10 / NULLIF(SUM(f.phyrds), 0), 2)  AS rd_ms,
       SUM(f.phywrts) AS writes,
       ROUND(SUM(f.writetim) * 10 / NULLIF(SUM(f.phywrts), 0), 2) AS wr_ms
FROM   v$filestat f
       JOIN v$datafile   d ON d.file# = f.file#
       JOIN v$tablespace t ON t.ts# = d.ts# AND t.con_id = d.con_id
GROUP  BY t.name
ORDER  BY SUM(f.readtim) DESC
FETCH FIRST 15 ROWS ONLY;

COLUMN file_name FORMAT a60 HEADING 'Busiest datafiles'
PROMPT
SELECT d.name AS file_name, f.phyrds AS reads,
       ROUND(f.readtim * 10 / NULLIF(f.phyrds, 0), 2) AS rd_ms
FROM   v$filestat f JOIN v$datafile d ON d.file# = f.file#
ORDER  BY f.phyrds DESC
FETCH FIRST 10 ROWS ONLY;

COLUMN thread#  FORMAT 990      HEADING 'Thread'
COLUMN groups   FORMAT 990      HEADING 'Groups'
COLUMN members  FORMAT 990      HEADING 'Members'
COLUMN size_mb  FORMAT 99,990   HEADING 'Size MB'
COLUMN per_hour FORMAT 990.0    HEADING 'Switches/hour (24h)'
PROMPT
PROMPT Online redo logs and switch rate over the last 24 hours
SELECT l.thread#, COUNT(*) AS groups, MAX(l.members) AS members,
       ROUND(MAX(l.bytes) / POWER(1024,2)) AS size_mb,
       ROUND((SELECT COUNT(*) FROM v$log_history h
              WHERE h.thread# = l.thread# AND h.first_time > SYSDATE - 1) / 24, 1) AS per_hour
FROM   v$log l
GROUP  BY l.thread#
ORDER  BY l.thread#;

PROMPT
PROMPT More than ~4-6 switches an hour at peak: make redo logs bigger (aim for one switch every 15-20 min).
PROMPT High "log file sync" with low "log file parallel write" = too many commits, not slow storage.
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@redo_and_io_latency_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f redo_and_io_latency_saved_settings.sql
