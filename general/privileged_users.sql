-- =============================================================
-- Script   : privileged_users.sql
-- Purpose  : Who holds powerful access: DBA role grantees, SYSDBA and
--            other administrative privileges in the password file, ANY
--            system privileges and grants made WITH ADMIN OPTION
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE
-- Where    : The PDB you want to check (or a non-CDB). Run it in each
--            PDB; CDB$ROOT shows the root only.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @privileged_users.sql
-- Settings : None.
-- Notes    : Lists application (non Oracle-maintained) grantees only, so
--            the output is short enough to review.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET privileged_users_saved_settings.sql REPLACE
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
TTITLE LEFT 'Privileged users   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN grantee      FORMAT a28 HEADING 'Grantee'
COLUMN granted_role FORMAT a24 HEADING 'Role'
COLUMN admin        FORMAT a5  HEADING 'Admin'
COLUMN account      FORMAT a20 HEADING 'Account status'
PROMPT
PROMPT Grantees of powerful roles (DBA, IMP/EXP_FULL_DATABASE, DATAPUMP_*, SELECT_CATALOG_ROLE ...)
SELECT r.grantee, r.granted_role, r.admin_option AS admin, NVL(u.account_status, '(role)') AS account
FROM   dba_role_privs r LEFT JOIN dba_users u ON u.username = r.grantee
WHERE  r.granted_role IN ('DBA', 'IMP_FULL_DATABASE', 'EXP_FULL_DATABASE', 'DATAPUMP_EXP_FULL_DATABASE',
                          'DATAPUMP_IMP_FULL_DATABASE', 'SELECT_CATALOG_ROLE', 'EXECUTE_CATALOG_ROLE',
                          'AUDIT_ADMIN', 'PDB_DBA', 'CDB_DBA')
AND    NVL(u.oracle_maintained, 'N') = 'N'
AND    r.grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained = 'Y')
ORDER  BY r.granted_role, r.grantee;

COLUMN username FORMAT a28 HEADING 'User in password file'
COLUMN privs    FORMAT a60 HEADING 'Administrative privileges'
PROMPT
PROMPT Users with SYSDBA / SYSOPER / SYSBACKUP / SYSDG / SYSKM / SYSRAC (password file)
SELECT username,
       RTRIM(DECODE(sysdba,'TRUE','SYSDBA ') || DECODE(sysoper,'TRUE','SYSOPER ') ||
             DECODE(sysbackup,'TRUE','SYSBACKUP ') || DECODE(sysdg,'TRUE','SYSDG ') ||
             DECODE(syskm,'TRUE','SYSKM ') || DECODE(sysasm,'TRUE','SYSASM ') ||
             DECODE(sysrac,'TRUE','SYSRAC ')) AS privs
FROM   v$pwfile_users
ORDER  BY username;

COLUMN privilege FORMAT a36 HEADING 'System privilege'
PROMPT
PROMPT ANY privileges and other powerful system privileges granted directly to application users or roles
SELECT p.grantee, p.privilege, p.admin_option AS admin
FROM   dba_sys_privs p
WHERE  (p.privilege LIKE '%ANY%' OR p.privilege IN ('ALTER SYSTEM', 'ALTER DATABASE', 'ALTER USER',
        'CREATE USER', 'DROP USER', 'GRANT ANY PRIVILEGE', 'GRANT ANY ROLE', 'BECOME USER',
        'EXEMPT ACCESS POLICY', 'EXEMPT REDACTION POLICY', 'AUDIT SYSTEM'))
AND    p.grantee NOT IN (SELECT username FROM dba_users WHERE oracle_maintained = 'Y')
AND    p.grantee NOT IN (SELECT role FROM dba_roles WHERE oracle_maintained = 'Y')
ORDER  BY p.grantee, p.privilege
FETCH FIRST 80 ROWS ONLY;

COLUMN cnt FORMAT 9,990 HEADING 'Privileges'
PROMPT
PROMPT Privileges granted to PUBLIC beyond the Oracle defaults (should be no rows)
SELECT 'PUBLIC' AS grantee, privilege, admin_option AS admin
FROM   dba_sys_privs
WHERE  grantee = 'PUBLIC' AND common = 'NO';

PROMPT
PROMPT Review with the application owner before revoking anything:  REVOKE <privilege> FROM <grantee>;
PROMPT For which privileges are actually used, see DBMS_PRIVILEGE_CAPTURE (no extra licence from 19c).
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con
SET TERMOUT OFF
@privileged_users_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f privileged_users_saved_settings.sql
