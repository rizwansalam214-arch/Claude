/* =============================================================================
   DIAGNOSTIC 02 — Collation and Jedoxdept quality (read-only)
   -----------------------------------------------------------------------------
   If BTL_LS_LIVE is case-sensitive (*_CS_*), every filter like
   Division_ID IN ('FRANCHISE') silently misses 'Franchise'. That alone can
   zero a block, and diagnose_summary_budget_zero.sql Step 5 uses mixed case.
   ============================================================================= */

-- 1. Database collations (CS = case-sensitive)
SELECT name, collation_name
FROM sys.databases
WHERE name IN (N'BTL_LS_LIVE', N'FAKHRA_LIVE');

-- 2. Every Division_ID as stored: exact spelling, case, hidden spaces
SELECT
    JD.Division_ID,
    N'[' + CAST(JD.Division_ID AS NVARCHAR(100)) + N']' AS Bracketed,   -- shows leading/trailing spaces
    DATALENGTH(JD.Division_ID) AS Bytes,
    JD.Division_Desc,
    COUNT(*) AS Departments
FROM BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
GROUP BY JD.Division_ID, JD.Division_Desc
ORDER BY UPPER(JD.Division_ID);

-- 3. Navision_IDs that are not plain integers (the old TRY_CONVERT(INT) join drops these)
SELECT JD.Navision_ID, JD.Division_ID, JD.Department_Desc
FROM BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
WHERE TRY_CONVERT(INT, JD.Navision_ID) IS NULL;

-- 4. Navision_IDs listed more than once (UAE and KSA share this table; a
--    duplicate means one company can pick up the other's division)
SELECT TRY_CONVERT(INT, JD.Navision_ID) AS DeptNo, COUNT(*) AS Rows,
       STRING_AGG(CAST(JD.Division_ID AS NVARCHAR(MAX)), N', ') AS Divisions
FROM BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
GROUP BY TRY_CONVERT(INT, JD.Navision_ID)
HAVING COUNT(*) > 1;
