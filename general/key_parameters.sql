-- =============================================================
-- Script   : key_parameters.sql
-- Purpose  : The init parameters that matter most, with value and where it
--            comes from; everything changed from the default; hidden
--            (underscore) and deprecated parameters; SPFILE vs memory
--            differences; RAC differences between instances
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : CDB$ROOT or non-CDB (PDB-level values show with
--            con_id > 1). RAC: compares all instances (GV$).
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @key_parameters.sql
-- Settings : None.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET key_parameters_saved_settings.sql REPLACE
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
TTITLE LEFT 'Key parameters   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN name    FORMAT a34 HEADING 'Parameter'
COLUMN value   FORMAT a50 HEADING 'Value' WORD_WRAPPED
COLUMN dflt    FORMAT a7  HEADING 'Default'
COLUMN src     FORMAT a9  HEADING 'Changed'
PROMPT
PROMPT Key parameters
SELECT name, display_value AS value,
       isdefault AS dflt,
       CASE ismodified WHEN 'FALSE' THEN '-' ELSE ismodified END AS src
FROM   v$parameter
WHERE  name IN ('db_name', 'db_unique_name', 'compatible', 'cluster_database', 'enable_pluggable_database',
                'sga_target', 'sga_max_size', 'pga_aggregate_target', 'pga_aggregate_limit', 'memory_target',
                'use_large_pages', 'db_cache_size', 'shared_pool_size', 'cpu_count', 'parallel_max_servers',
                'processes', 'sessions', 'open_cursors', 'session_cached_cursors', 'job_queue_processes',
                'db_recovery_file_dest', 'db_recovery_file_dest_size', 'log_archive_dest_1', 'undo_retention',
                'undo_tablespace', 'db_block_size', 'db_files', 'control_file_record_keep_time',
                'optimizer_features_enable', 'optimizer_adaptive_plans', 'optimizer_adaptive_statistics',
                'audit_trail', 'remote_login_passwordfile', 'resource_limit', 'sec_case_sensitive_logon',
                'db_securefile', 'filesystemio_options', 'disk_asynch_io', 'local_listener', 'remote_listener',
                'spfile', 'diagnostic_dest', 'max_string_size', 'enable_ddl_logging')
ORDER  BY name;

PROMPT
PROMPT All parameters changed from the default (not counting the ones listed above)
SELECT name, display_value AS value
FROM   v$parameter
WHERE  isdefault = 'FALSE'
AND    name NOT LIKE '\_%' ESCAPE '\'
AND    name NOT IN ('db_name', 'db_unique_name', 'compatible', 'control_files', 'spfile', 'db_domain',
                    'sga_target', 'pga_aggregate_target', 'processes', 'audit_file_dest', 'diagnostic_dest',
                    'db_recovery_file_dest', 'db_recovery_file_dest_size', 'local_listener', 'remote_listener',
                    'db_block_size', 'undo_tablespace', 'open_cursors', 'log_archive_dest_1', 'cluster_database',
                    'enable_pluggable_database', 'use_large_pages', 'sga_max_size', 'memory_target',
                    'job_queue_processes', 'sessions', 'cpu_count', 'remote_login_passwordfile', 'audit_trail')
ORDER  BY name;

PROMPT
PROMPT Hidden (underscore) parameters that are set - each should have a reason (an SR or a MOS note)
SELECT name, display_value AS value FROM v$parameter
WHERE  name LIKE '\_%' ESCAPE '\' AND isdefault = 'FALSE'
ORDER  BY name;

PROMPT
PROMPT Deprecated parameters that are still set (remove before the next upgrade)
SELECT name, display_value AS value FROM v$parameter
WHERE  isdeprecated = 'TRUE' AND isdefault = 'FALSE'
ORDER  BY name;

COLUMN mem_value FORMAT a40 HEADING 'In memory'
COLUMN spf_value FORMAT a40 HEADING 'In SPFILE'
PROMPT
PROMPT Memory vs SPFILE differences (these values change at the next restart)
SELECT p.name, p.display_value AS mem_value, NVL(s.display_value, '(not in SPFILE)') AS spf_value
FROM   v$parameter p
       JOIN v$spparameter s ON s.name = p.name AND s.sid IN ('*', SYS_CONTEXT('USERENV', 'INSTANCE_NAME'))
WHERE  s.isspecified = 'TRUE'
AND    NVL(s.display_value, '~') <> NVL(p.display_value, '~')
AND    p.name NOT IN ('control_files')
ORDER  BY p.name;

COLUMN insts FORMAT a40 HEADING 'Value by instance'
PROMPT
PROMPT RAC: parameters with different values on different instances (no rows on single instance)
SELECT name,
       LISTAGG(inst_id || '=' || SUBSTR(display_value, 1, 20), '  ') WITHIN GROUP (ORDER BY inst_id) AS insts
FROM   gv$parameter
WHERE  name NOT IN ('instance_number', 'instance_name', 'thread', 'undo_tablespace', 'local_listener',
                    'core_dump_dest', 'background_dump_dest', 'user_dump_dest', 'audit_file_dest',
                    'service_names', 'cluster_interconnects', 'spfile')
GROUP  BY name
HAVING COUNT(DISTINCT NVL(display_value, '~')) > 1
ORDER  BY name;

COLUMN resource_name FORMAT a22       HEADING 'Resource'
COLUMN current_utilization FORMAT 999,990 HEADING 'Now'
COLUMN max_utilization FORMAT 999,990 HEADING 'Peak'
COLUMN limit_value     FORMAT a10     HEADING 'Limit'
COLUMN pct_peak        FORMAT 990     HEADING 'Peak %'
PROMPT
PROMPT Resource limits since startup (Peak % over 80 = raise the parameter before you run out)
SELECT resource_name, current_utilization, max_utilization, TRIM(limit_value) AS limit_value,
       ROUND(max_utilization / NULLIF(TO_NUMBER(DECODE(TRIM(limit_value), 'UNLIMITED', NULL, TRIM(limit_value))), 0) * 100) AS pct_peak
FROM   v$resource_limit
WHERE  resource_name IN ('processes', 'sessions', 'transactions', 'enqueue_locks', 'parallel_max_servers',
                         'max_shared_servers')
ORDER  BY resource_name;

PROMPT
PROMPT Change a parameter for memory and SPFILE together:  ALTER SYSTEM SET <name> = <value> SCOPE=BOTH SID='*';
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@key_parameters_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f key_parameters_saved_settings.sql
