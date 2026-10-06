/* =============================================================================
   DIAGNOSTIC 03 — SNS and Franchise Division_ID (read-only)
   -----------------------------------------------------------------------------
   Replaces sns_franchise_check.sql. The original compared
   Division_ID = 'Franchise' (mixed case); on a case-sensitive database that
   misses 'FRANCHISE', which is what the extracts filter on. UPPER() here makes
   the check independent of case.
   ============================================================================= */

-- 1. Anything that looks like SNS / Shop / Franchise, whatever the case
SELECT DISTINCT JD.Division_ID, JD.Division_Desc, JD.Department_Desc, JD.Navision_ID
FROM BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
WHERE UPPER(JD.Division_ID)   LIKE N'%SNS%'
   OR UPPER(JD.Division_Desc) LIKE N'%SNS%'
   OR UPPER(JD.Division_Desc) LIKE N'%SHOP%'
   OR UPPER(JD.Division_ID)   LIKE N'%FRANCH%'
ORDER BY JD.Division_ID, JD.Navision_ID;

-- 2. Did any of those departments actually sell this year? (UAE and KSA)
SELECT N'UAE' AS Company, JD.Division_ID, VE.[Global Dimension 2 Code] AS DeptCode,
       SUM(VE.[Sales Amount (Actual)]) AS SalesYTD
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
JOIN BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
  ON TRY_CONVERT(INT, JD.Navision_ID) = TRY_CONVERT(INT, VE.[Global Dimension 2 Code])
WHERE VE.[Item Ledger Entry Type] = 1
  AND VE.[Posting Date] >= DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
  AND (UPPER(JD.Division_ID) LIKE N'%SNS%' OR UPPER(JD.Division_ID) LIKE N'%FRANCH%')
GROUP BY JD.Division_ID, VE.[Global Dimension 2 Code]
UNION ALL
SELECT N'KSA', JD.Division_ID, VE.[Global Dimension 2 Code], SUM(VE.[Sales Amount (Actual)])
FROM BTL_LS_LIVE.dbo.[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
JOIN BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
  ON TRY_CONVERT(INT, JD.Navision_ID) = TRY_CONVERT(INT, VE.[Global Dimension 2 Code])
WHERE VE.[Item Ledger Entry Type] = 1
  AND VE.[Posting Date] >= DATEFROMPARTS(YEAR(GETDATE()), 1, 1)
  AND (UPPER(JD.Division_ID) LIKE N'%SNS%' OR UPPER(JD.Division_ID) LIKE N'%FRANCH%')
GROUP BY JD.Division_ID, VE.[Global Dimension 2 Code]
ORDER BY 1, 2, 3;

-- Action: put the exact SNS Division_ID (upper-cased) into cfg.SegmentRule
-- (RuleType DIVISION) and set its Status to AGREED.
