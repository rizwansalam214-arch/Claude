/* =============================================================================
   DIAGNOSTIC 04 — Al Fakhra: budget name, department codes, unmapped sales
   (read-only). Combines and corrects fakhra_budget_name_check.sql and
   fakhra_department_code_check.sql (which omitted 017 and did not restrict
   names to the Global Dimension 1 dimension).
   ============================================================================= */

-- 1. Budget names actually stored (case and spacing matter)
SELECT
    B.[Budget Name],
    N'[' + B.[Budget Name] + N']' AS Bracketed,
    MIN(B.[Date]) AS FirstDate,
    MAX(B.[Date]) AS LastDate,
    COUNT(*)      AS Rows,
    SUM(CASE WHEN LEFT(B.[G_L Account No_], 1) = N'3' THEN -B.[Amount] ELSE 0 END) AS SalesBudget
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B WITH (NOLOCK)
GROUP BY B.[Budget Name]
ORDER BY MAX(B.[Date]) DESC;
-- Action: put the 2026 name into cfg.BudgetVersion (Company FAKHRA) and set Status AGREED.

-- 2. Which dimension IS Global Dimension 1 in Al Fakhra
SELECT GS.[Global Dimension 1 Code], GS.[Global Dimension 2 Code]
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$General Ledger Setup$437dbf0e-84ff-417a-965d-ed2bb9650972] GS WITH (NOLOCK);

-- 3. Names of all eight mapped codes, from that dimension only (017 included)
SELECT LTRIM(RTRIM(DV.[Code])) AS DeptCode, DV.[Name] AS DeptName, DV.[Dimension Code]
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DV WITH (NOLOCK)
JOIN FAKHRA_LIVE.dbo.[Al Fakhra Date$General Ledger Setup$437dbf0e-84ff-417a-965d-ed2bb9650972] GS WITH (NOLOCK)
  ON GS.[Global Dimension 1 Code] = DV.[Dimension Code]
WHERE LTRIM(RTRIM(DV.[Code])) IN (N'011', N'011-1', N'013-1', N'014', N'015', N'016', N'017', N'018')
ORDER BY DeptCode;
-- Confirm: 017 = KSA Private Label; none of the eight is an inter-company
-- (sales to Bateel UAE/KSA) department.

-- 4. Sales by department code, this year and last, flagged if not mapped.
--    Anything unmapped with material sales is currently missing from every extract.
SELECT
    LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N''))) AS DeptCode,
    CASE WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N'')))
              IN (N'011', N'011-1', N'013-1', N'014', N'015', N'016', N'017', N'018')
         THEN N'mapped' ELSE N'NOT MAPPED' END AS MappingStatus,
    SUM(CASE WHEN YEAR(VE.[Posting Date]) = YEAR(GETDATE())     THEN VE.[Sales Amount (Actual)] ELSE 0 END) AS SalesThisYear,
    SUM(CASE WHEN YEAR(VE.[Posting Date]) = YEAR(GETDATE()) - 1 THEN VE.[Sales Amount (Actual)] ELSE 0 END) AS SalesLastYear
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
WHERE VE.[Item Ledger Entry Type] = 1
  AND VE.[Posting Date] >= DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1)
GROUP BY LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N'')))
ORDER BY SalesThisYear DESC;
