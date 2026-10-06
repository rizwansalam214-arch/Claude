/* =============================================================================
   DIAGNOSTIC 05 — Year-end closing entries on revenue accounts (read-only)
   -----------------------------------------------------------------------------
   BC posts the income-statement close on a closing date, stored as 23:59:59.
   Any G/L query spanning a closed year end without excluding these entries
   shows December revenue at (near) zero. Both old extracts start on 1 Jan so
   they never hit this; 24 months of history will.
   ============================================================================= */

SELECT N'UAE' AS Company, YEAR(G.[Posting Date]) AS FiscalYear, COUNT(*) AS ClosingRows, SUM(G.[Amount]) AS Amount
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND CONVERT(TIME(0), G.[Posting Date]) = '23:59:59'
GROUP BY YEAR(G.[Posting Date])
UNION ALL
SELECT N'KSA', YEAR(G.[Posting Date]), COUNT(*), SUM(G.[Amount])
FROM BTL_LS_LIVE.dbo.[BATEEL-KSA$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND CONVERT(TIME(0), G.[Posting Date]) = '23:59:59'
GROUP BY YEAR(G.[Posting Date])
UNION ALL
SELECT N'FAKHRA', YEAR(G.[Posting Date]), COUNT(*), SUM(G.[Amount])
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND CONVERT(TIME(0), G.[Posting Date]) = '23:59:59'
GROUP BY YEAR(G.[Posting Date])
ORDER BY 1, 2;
-- Expected: one block per closed year, Amount positive (debit clears the
-- credit balance). rpt.vSalesGL excludes these rows.
