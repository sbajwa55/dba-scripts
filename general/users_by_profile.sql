-- =============================================================
-- Script   : users_by_profile.sql
-- Purpose  : User accounts summarised: how many users per profile and
--            account status, accounts that are expired, locked or about
--            to expire, accounts never used, and default passwords
-- Section  : General
-- Database : Oracle 19c, 21c (CDB or non-CDB; RAC and Exadata)
-- Run as   : SYSTEM or a user with SELECT_CATALOG_ROLE (DBA_USERS_WITH_DEFPWD needs SYS or the DBA role)
-- Where    : The PDB you want to check (or a non-CDB). Run it in each
--            PDB; CDB$ROOT shows the root only.
-- Changes  : None (read-only)
-- Client   : SQL*Plus      Usage: SQL> @users_by_profile.sql
-- Settings : "expire_days" = warn about passwords expiring within
--            this many days; "unused_days" = no login for this long.
-- Notes    : Oracle-maintained accounts (SYS, SYSTEM, ...) are counted
--            separately so they do not hide your application users.
-- Author   : Sandeep S. Bajwa · bajwaconsulting.com
-- =============================================================
DEFINE expire_days = 14
DEFINE unused_days = 90
-- ---------- Save current SQL*Plus settings ---------------------
SET TERMOUT OFF
STORE SET users_by_profile_saved_settings.sql REPLACE
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
TTITLE LEFT 'Users by profile   ' _DATE SKIP 1 LEFT 'Database: ' v_db '   Container: ' v_con SKIP 1 LEFT '=============================================' SKIP 1

COLUMN profile        FORMAT a26     HEADING 'Profile'
COLUMN kind           FORMAT a8      HEADING 'Kind'
COLUMN total          FORMAT 99,990  HEADING 'Users'
COLUMN open_cnt       FORMAT 99,990  HEADING 'Open'
COLUMN locked         FORMAT 99,990  HEADING 'Locked'
COLUMN expired        FORMAT 99,990  HEADING 'Expired'
COLUMN grace          FORMAT 99,990  HEADING 'In grace'
BREAK ON REPORT
COMPUTE SUM LABEL 'Total' OF total open_cnt locked expired grace ON REPORT
PROMPT
PROMPT Users per profile and account status
SELECT profile,
       DECODE(oracle_maintained, 'Y', 'Oracle', 'App') AS kind,
       COUNT(*) AS total,
       SUM(CASE WHEN account_status = 'OPEN' THEN 1 ELSE 0 END)         AS open_cnt,
       SUM(CASE WHEN account_status LIKE '%LOCKED%' THEN 1 ELSE 0 END)  AS locked,
       SUM(CASE WHEN account_status LIKE 'EXPIRED%' AND account_status NOT LIKE '%GRACE%' THEN 1 ELSE 0 END) AS expired,
       SUM(CASE WHEN account_status LIKE '%GRACE%' THEN 1 ELSE 0 END)   AS grace
FROM   dba_users
GROUP  BY profile, oracle_maintained
ORDER  BY oracle_maintained, total DESC;
CLEAR BREAKS
CLEAR COMPUTES

COLUMN account_status FORMAT a26 HEADING 'Account status'
PROMPT
PROMPT Application users by account status
SELECT account_status, COUNT(*) AS total
FROM   dba_users
WHERE  oracle_maintained = 'N'
GROUP  BY account_status
ORDER  BY total DESC;

COLUMN username    FORMAT a26 HEADING 'User'
COLUMN expiry      FORMAT a15 HEADING 'Password expires'
COLUMN last_login  FORMAT a15 HEADING 'Last login'
COLUMN created     FORMAT a10 HEADING 'Created'
PROMPT
PROMPT Open application users whose password expires in the next &expire_days days (or is in grace)
SELECT username, profile, account_status,
       TO_CHAR(expiry_date, 'DD-MON-YY HH24:MI') AS expiry,
       TO_CHAR(last_login, 'DD-MON-YY HH24:MI') AS last_login
FROM   dba_users
WHERE  oracle_maintained = 'N'
AND   (account_status LIKE '%GRACE%' OR (account_status = 'OPEN' AND expiry_date < SYSDATE + &expire_days))
ORDER  BY expiry_date;

PROMPT
PROMPT Open application users with no login in &unused_days days (candidates to lock)
SELECT username, profile,
       NVL(TO_CHAR(last_login, 'DD-MON-YY HH24:MI'), 'never') AS last_login,
       TO_CHAR(created, 'DD-MON-YY') AS created
FROM   dba_users
WHERE  oracle_maintained = 'N'
AND    account_status = 'OPEN'
AND    authentication_type = 'PASSWORD'
AND    NVL(CAST(last_login AS DATE), created) < SYSDATE - &unused_days
ORDER  BY last_login NULLS FIRST
FETCH FIRST 50 ROWS ONLY;

PROMPT
PROMPT Open accounts still using a default password (should be no rows)
SELECT d.username, u.account_status
FROM   dba_users_with_defpwd d JOIN dba_users u ON u.username = d.username
WHERE  u.account_status = 'OPEN';

COLUMN password_versions FORMAT a17 HEADING 'Password versions'
PROMPT
PROMPT Accounts with only an old 10G password hash (cannot log in when SQLNET.ALLOWED_LOGON_VERSION_SERVER=12)
SELECT username, account_status, password_versions
FROM   dba_users
WHERE  oracle_maintained = 'N'
AND    TRIM(password_versions) = '10G'
ORDER  BY username;

PROMPT
PROMPT Profile limits: general/profile_limits.sql.  Lock an unused account:  ALTER USER <name> ACCOUNT LOCK;
PROMPT

-- ---------- Restore SQL*Plus settings --------------------------
TTITLE OFF
BTITLE OFF
CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
UNDEFINE v_db v_con expire_days unused_days
SET TERMOUT OFF
@users_by_profile_saved_settings.sql
SET TERMOUT ON
-- Linux/Unix; on Windows change "rm -f" to "del"
HOST rm -f users_by_profile_saved_settings.sql
