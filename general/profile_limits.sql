-- =============================================================
-- Script   : profile_limits.sql
-- Purpose  : Every profile with its resource and password limits side by
--            side (DEFAULT resolved to the real value), how many users
--            use it, whether resource limits are enforced, and users
--            close to their SESSIONS_PER_USER limit right now
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB you want to check (or a non-CDB). Run it in each
--            PDB; CDB$ROOT shows the root only.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @profile_limits.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET profile_limits_saved_settings.sql REPLACE
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
TTITLE LEFT 'Profile limits   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN profile     FORMAT a24 HEADING 'Profile'
COLUMN users       FORMAT 9,990 HEADING 'Users'
COLUMN sess        FORMAT a9  HEADING 'Sessions/ user'
COLUMN idle        FORMAT a9  HEADING 'Idle min'
COLUMN conn        FORMAT a9  HEADING 'Connect min'
COLUMN fail        FORMAT a9  HEADING 'Failed logins'
COLUMN lock_t      FORMAT a9  HEADING 'Lock days'
COLUMN life        FORMAT a9  HEADING 'Pwd life days'
COLUMN grace       FORMAT a9  HEADING 'Grace days'
COLUMN reuse_max   FORMAT a9  HEADING 'Reuse max'
COLUMN reuse_time  FORMAT a9  HEADING 'Reuse days'
COLUMN inactive    FORMAT a9  HEADING 'Inactive days'
COLUMN verify      FORMAT a22 HEADING 'Verify function'
PROMPT
PROMPT Limits per profile (DEFAULT is shown as the value it takes from the DEFAULT profile)
WITH lim AS (
  SELECT p.profile, p.resource_name,
         CASE WHEN p.limit = 'DEFAULT' THEN d.limit ELSE p.limit END AS limit
  FROM   dba_profiles p
         JOIN dba_profiles d ON d.profile = 'DEFAULT' AND d.resource_name = p.resource_name)
SELECT l.profile,
       (SELECT COUNT(*) FROM dba_users u WHERE u.profile = l.profile) AS users,
       MAX(DECODE(resource_name, 'SESSIONS_PER_USER',         limit)) AS sess,
       MAX(DECODE(resource_name, 'IDLE_TIME',                 limit)) AS idle,
       MAX(DECODE(resource_name, 'CONNECT_TIME',              limit)) AS conn,
       MAX(DECODE(resource_name, 'FAILED_LOGIN_ATTEMPTS',     limit)) AS fail,
       MAX(DECODE(resource_name, 'PASSWORD_LOCK_TIME',        limit)) AS lock_t,
       MAX(DECODE(resource_name, 'PASSWORD_LIFE_TIME',        limit)) AS life,
       MAX(DECODE(resource_name, 'PASSWORD_GRACE_TIME',       limit)) AS grace,
       MAX(DECODE(resource_name, 'PASSWORD_REUSE_MAX',        limit)) AS reuse_max,
       MAX(DECODE(resource_name, 'PASSWORD_REUSE_TIME',       limit)) AS reuse_time,
       MAX(DECODE(resource_name, 'INACTIVE_ACCOUNT_TIME',     limit)) AS inactive,
       MAX(DECODE(resource_name, 'PASSWORD_VERIFY_FUNCTION',  limit)) AS verify
FROM   lim l
GROUP  BY l.profile
ORDER  BY users DESC, l.profile;

COLUMN resource_name FORMAT a28 HEADING 'Other limits not UNLIMITED'
COLUMN limit         FORMAT a20 HEADING 'Limit'
BREAK ON profile SKIP 1
PROMPT
SELECT profile, resource_name, limit
FROM   dba_profiles
WHERE  resource_name IN ('CPU_PER_SESSION', 'CPU_PER_CALL', 'LOGICAL_READS_PER_SESSION', 'LOGICAL_READS_PER_CALL',
                         'PRIVATE_SGA', 'COMPOSITE_LIMIT', 'PASSWORD_ROLLOVER_TIME')
AND    limit NOT IN ('UNLIMITED', 'DEFAULT', '0')
ORDER  BY profile, resource_name;
CLEAR BREAKS

COLUMN name  FORMAT a24 HEADING 'Parameter'
COLUMN value FORMAT a10 HEADING 'Value'
PROMPT
PROMPT RESOURCE_LIMIT must be TRUE for SESSIONS_PER_USER, IDLE_TIME and other kernel limits to be enforced
PROMPT (password limits are always enforced)
SELECT name, value FROM v$parameter WHERE name = 'resource_limit';

COLUMN username FORMAT a26  HEADING 'User'
COLUMN now      FORMAT 9,990 HEADING 'Sessions now'
COLUMN lim      FORMAT a10  HEADING 'Limit'
PROMPT
PROMPT Users at 80% or more of their SESSIONS_PER_USER limit right now (all RAC instances)
WITH lim AS (
  SELECT p.profile, CASE WHEN p.limit = 'DEFAULT' THEN d.limit ELSE p.limit END AS limit
  FROM   dba_profiles p
         JOIN dba_profiles d ON d.profile = 'DEFAULT' AND d.resource_name = p.resource_name
  WHERE  p.resource_name = 'SESSIONS_PER_USER')
SELECT s.username, u.profile, COUNT(*) AS now, l.limit AS lim
FROM   gv$session s
       JOIN dba_users u ON u.username = s.username
       JOIN lim l       ON l.profile  = u.profile
WHERE  s.type = 'USER'
AND    l.limit <> 'UNLIMITED'
GROUP  BY s.username, u.profile, l.limit
HAVING COUNT(*) >= 0.8 * TO_NUMBER(l.limit)
ORDER  BY now DESC;

PROMPT
PROMPT Change a limit:  ALTER PROFILE <profile> LIMIT FAILED_LOGIN_ATTEMPTS 5;
PROMPT Move a user:     ALTER USER <name> PROFILE <profile>;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@profile_limits_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f profile_limits_saved_settings.sql
