-- =============================================================
-- Script   : asm_diskgroup_health.sql
-- Purpose  : ASM health: disk group size, free and USABLE space (after
--            mirroring), redundancy, compatibility, disks that are not
--            online, imbalance between disks, and running rebalances
-- Section  : High Availability / RAC
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM / SELECT_CATALOG_ROLE in a database, or SYSASM in +ASM
-- Where    : A database instance or the ASM instance (+ASM, as SYSASM).
--            Works on Exadata (grid disks) and standard RAC.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @asm_diskgroup_health.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET asm_diskgroup_health_saved_settings.sql REPLACE
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
TTITLE LEFT 'ASM disk group health   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN dg        FORMAT a12        HEADING 'Disk group'
COLUMN type      FORMAT a6         HEADING 'Redund'
COLUMN state     FORMAT a10        HEADING 'State'
COLUMN total_gb  FORMAT 9,999,990  HEADING 'Total GB'
COLUMN free_gb   FORMAT 9,999,990  HEADING 'Free GB'
COLUMN usable_gb FORMAT 9,999,990  HEADING 'Usable GB'
COLUMN pct_used  FORMAT 990        HEADING 'Used %'
COLUMN offline   FORMAT 990        HEADING 'Offline disks'
COLUMN compat    FORMAT a22        HEADING 'ASM / DB compatible'
PROMPT
PROMPT Disk groups (Usable GB = space you can still use after mirroring; negative = cannot survive a disk failure)
SELECT name AS dg, type, state,
       ROUND(total_mb / 1024) AS total_gb,
       ROUND(free_mb  / 1024) AS free_gb,
       ROUND(usable_file_mb / 1024) AS usable_gb,
       ROUND((total_mb - free_mb) / NULLIF(total_mb, 0) * 100) AS pct_used,
       offline_disks AS offline,
       compatibility || ' / ' || database_compatibility AS compat
FROM   v$asm_diskgroup
ORDER  BY name;

COLUMN path        FORMAT a40 HEADING 'Disk path'
COLUMN disk_name   FORMAT a24 HEADING 'Disk'
COLUMN mode_status FORMAT a8  HEADING 'Mode'
COLUMN header      FORMAT a12 HEADING 'Header'
COLUMN mount       FORMAT a8  HEADING 'Mount'
PROMPT
PROMPT Disks that are not ONLINE/CACHED/NORMAL (should be no rows), plus CANDIDATE disks you could add
SELECT NVL(g.name, '-') AS dg, d.name AS disk_name, d.path, d.mode_status, d.header_status AS header,
       d.mount_status AS mount, d.state
FROM   v$asm_disk d LEFT JOIN v$asm_diskgroup g ON g.group_number = d.group_number
WHERE  d.mode_status <> 'ONLINE' OR d.mount_status NOT IN ('CACHED') OR d.state <> 'NORMAL'
   OR  d.header_status IN ('CANDIDATE', 'PROVISIONED', 'FORMER')
ORDER  BY 1, 2;

COLUMN disks    FORMAT 9,990 HEADING 'Disks'
COLUMN min_free FORMAT 990.0 HEADING 'Min free %'
COLUMN max_free FORMAT 990.0 HEADING 'Max free %'
COLUMN spread   FORMAT 990.0 HEADING 'Spread'
PROMPT
PROMPT Balance between disks in each group (Spread > ~10 points = disks unevenly filled, rebalance needed)
SELECT g.name AS dg, COUNT(*) AS disks,
       ROUND(MIN(d.free_mb / NULLIF(d.total_mb, 0) * 100), 1) AS min_free,
       ROUND(MAX(d.free_mb / NULLIF(d.total_mb, 0) * 100), 1) AS max_free,
       ROUND(MAX(d.free_mb / NULLIF(d.total_mb, 0) * 100) - MIN(d.free_mb / NULLIF(d.total_mb, 0) * 100), 1) AS spread
FROM   v$asm_disk d JOIN v$asm_diskgroup g ON g.group_number = d.group_number
WHERE  d.mount_status = 'CACHED'
GROUP  BY g.name
ORDER  BY g.name;

COLUMN operation FORMAT a8     HEADING 'Op'
COLUMN pass      FORMAT a10    HEADING 'Pass'
COLUMN power     FORMAT 990    HEADING 'Power'
COLUMN est_min   FORMAT 99,990 HEADING 'Est. minutes left'
PROMPT
PROMPT Running ASM operations (rebalance, resync)
SELECT g.name AS dg, o.operation, o.pass, o.state, o.power, o.est_minutes AS est_min
FROM   gv$asm_operation o JOIN v$asm_diskgroup g ON g.group_number = o.group_number;

PROMPT
PROMPT Keep NORMAL redundancy groups with Usable GB above zero, so a failed disk can be re-mirrored.
PROMPT Speed up a rebalance (in +ASM):  ALTER DISKGROUP <dg> REBALANCE POWER 8;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@asm_diskgroup_health_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f asm_diskgroup_health_saved_settings.sql
