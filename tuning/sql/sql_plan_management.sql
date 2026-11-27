-- =============================================================
-- Script   : sql_plan_management.sql
-- Purpose  : What is fixing SQL plans in this database: SQL plan
--            baselines, SQL profiles and SQL patches, with their status,
--            and the SPM settings. Useful when a plan "will not change".
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB (or non-CDB) where the SQL runs.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @sql_plan_management.sql
-- Settings : "days_back" = only show items used or created in this
--            many days (use 9999 for everything).
-- Notes    : Reading these views needs no extra licence. Creating SQL
--            profiles needs the Tuning Pack; plan baselines do not.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE days_back = 9999
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET sql_plan_management_saved_settings.sql REPLACE
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
TTITLE LEFT 'SQL plan management   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN name    FORMAT a42 HEADING 'Parameter'
COLUMN value   FORMAT a10 HEADING 'Value'
PROMPT
PROMPT SPM settings
SELECT name, value FROM v$parameter
WHERE  name IN ('optimizer_use_sql_plan_baselines', 'optimizer_capture_sql_plan_baselines',
                'optimizer_features_enable', 'optimizer_adaptive_plans');

COLUMN sql_handle FORMAT a22 HEADING 'SQL handle'
COLUMN plan_name  FORMAT a32 HEADING 'Plan name'
COLUMN flags      FORMAT a11 HEADING 'Ena/Acc/Fix'
COLUMN origin     FORMAT a20 HEADING 'Origin'
COLUMN created    FORMAT a15 HEADING 'Created'
COLUMN last_exec  FORMAT a15 HEADING 'Last used'
COLUMN sql_text   FORMAT a40 HEADING 'SQL text' TRUNCATED
PROMPT
PROMPT SQL plan baselines (Ena/Acc/Fix = enabled, accepted, fixed)
SELECT sql_handle, plan_name,
       enabled || '/' || accepted || '/' || fixed AS flags,
       origin,
       TO_CHAR(created, 'DD-MON-YY HH24:MI') AS created,
       TO_CHAR(last_executed, 'DD-MON-YY HH24:MI') AS last_exec,
       SUBSTR(sql_text, 1, 40) AS sql_text
FROM   dba_sql_plan_baselines
WHERE  GREATEST(created, NVL(last_executed, created)) > SYSDATE - &days_back
ORDER  BY created DESC
FETCH FIRST 50 ROWS ONLY;

COLUMN pname    FORMAT a32 HEADING 'Name'
COLUMN category FORMAT a10 HEADING 'Category'
COLUMN status   FORMAT a9  HEADING 'Status'
COLUMN kind     FORMAT a8  HEADING 'Kind'
PROMPT
PROMPT SQL profiles and SQL patches
SELECT 'PROFILE' AS kind, name AS pname, category, status,
       TO_CHAR(created, 'DD-MON-YY HH24:MI') AS created, SUBSTR(sql_text, 1, 40) AS sql_text
FROM   dba_sql_profiles
WHERE  created > SYSDATE - &days_back
UNION ALL
SELECT 'PATCH', name, category, status,
       TO_CHAR(created, 'DD-MON-YY HH24:MI'), SUBSTR(sql_text, 1, 40)
FROM   dba_sql_patches
WHERE  created > SYSDATE - &days_back
ORDER  BY 5 DESC;

PROMPT
PROMPT Which SQL_ID uses which baseline/profile/patch: tuning/sql/sql_details.sql <sql_id>
PROMPT Show a baseline plan:  SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_SQL_PLAN_BASELINE(plan_name => '<plan_name>'));
PROMPT Disable instead of drop (easy to undo):
PROMPT   DECLARE n PLS_INTEGER; BEGIN n := DBMS_SPM.ALTER_SQL_PLAN_BASELINE(sql_handle => '<h>',
PROMPT     plan_name => '<p>', attribute_name => 'ENABLED', attribute_value => 'NO'); END;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con days_back
SET TERMOUT OFF
@sql_plan_management_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f sql_plan_management_saved_settings.sql
