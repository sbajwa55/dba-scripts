-- =============================================================
-- Script   : sql_tuning_advisor.sql
-- Purpose  : Run the SQL Tuning Advisor on one SQL_ID that is in the
--            shared pool and print its findings and recommendations
--            (new indexes, statistics, SQL profile, rewrites)
-- Section  : Tuning / SQL
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : A user with the ADVISOR privilege and SELECT_CATALOG_ROLE
-- Where    : The PDB (or non-CDB) where the SQL runs.
-- Changes  : Creates (and replaces) an advisor task named STA_<sql_id>.
--            It does NOT apply any recommendation; you decide.
-- Client   : SQL*Plus      Usage: SQL> @sql_tuning_advisor.sql <sql_id>
-- Settings : SQL_ID is the first argument. "time_limit" = seconds
--            the advisor may spend (default 300).
-- Notes    : Needs the Oracle Tuning Pack licence (and Diagnostics Pack).
--            Do not run it if you are not licensed.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE sql_id = '&1'
DEFINE time_limit = 300
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET sql_tuning_advisor_saved_settings.sql REPLACE
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
TTITLE LEFT 'SQL Tuning Advisor   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

SET SERVEROUTPUT ON
PROMPT
PROMPT Running the SQL Tuning Advisor for &sql_id (up to &time_limit seconds) ...
BEGIN
  BEGIN
    DBMS_SQLTUNE.DROP_TUNING_TASK(task_name => 'STA_&sql_id');
  EXCEPTION
    WHEN OTHERS THEN NULL;   -- no earlier task with this name
  END;
  DBMS_OUTPUT.PUT_LINE('Task: ' ||
    DBMS_SQLTUNE.CREATE_TUNING_TASK(sql_id      => '&sql_id',
                                    scope       => DBMS_SQLTUNE.SCOPE_COMPREHENSIVE,
                                    time_limit  => &time_limit,
                                    task_name   => 'STA_&sql_id',
                                    description => 'bajwaconsulting sql_tuning_advisor.sql'));
  DBMS_SQLTUNE.EXECUTE_TUNING_TASK(task_name => 'STA_&sql_id');
END;
/
SET SERVEROUTPUT OFF

SET LONG 1000000
SET LONGCHUNKSIZE 1000000
SET PAGESIZE 0
SET HEADING OFF
TTITLE OFF
COLUMN report FORMAT a200
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('STA_&sql_id') AS report FROM dual;
SET HEADING ON
SET PAGESIZE 200

PROMPT
PROMPT Each recommendation in the report shows the exact command to apply it. Test it first.
PROMPT SQL not in the shared pool any more? Create the task from AWR instead:
PROMPT   DBMS_SQLTUNE.CREATE_TUNING_TASK(begin_snap => <b>, end_snap => <e>, sql_id => '&sql_id', ...)
PROMPT Remove the task when finished:  EXEC DBMS_SQLTUNE.DROP_TUNING_TASK('STA_&sql_id');
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con sql_id time_limit 1
SET TERMOUT OFF
@sql_tuning_advisor_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f sql_tuning_advisor_saved_settings.sql
