/* =============================================================================
   DIAGNOSTIC 01 — Sign convention (read-only, run in SSMS)
   -----------------------------------------------------------------------------
   The semantic layer assumes BC's standard signs:
     Value Entry  [Sales Amount (Actual)]       POSITIVE for sales
                  [Item Ledger Entry Quantity]  NEGATIVE for sales
     G/L Entry    [Amount] on 3* accounts       NEGATIVE (credit)
     G/L Budget   [Amount] on 3* accounts       NEGATIVE (if entered like G/L)

   If the results match, the old extracts were wrong as follows:
     channel_sku_extract.sql  actual Sales/Qty came out NEGATIVE (-Sales Amount)
     summary_gl_extract.sql   budget Sales came out NEGATIVE (+Amount)
   Last full month is used so cost/sales adjustments have settled.
   ============================================================================= */

DECLARE @From DATE = DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));
DECLARE @To   DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);

SELECT N'UAE' AS Company, N'Value Entry sale' AS Source,
       SUM(VE.[Sales Amount (Actual)]) AS SumAmount,
       SUM(VE.[Item Ledger Entry Quantity]) AS SumQty,
       SUM(CASE WHEN VE.[Sales Amount (Actual)] > 0 THEN 1 ELSE 0 END) AS PositiveRows,
       SUM(CASE WHEN VE.[Sales Amount (Actual)] < 0 THEN 1 ELSE 0 END) AS NegativeRows
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
WHERE VE.[Item Ledger Entry Type] = 1 AND VE.[Posting Date] >= @From AND VE.[Posting Date] < @To
UNION ALL
SELECT N'UAE', N'G/L 3* excl. Other Income', SUM(G.[Amount]), NULL,
       SUM(CASE WHEN G.[Amount] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN G.[Amount] < 0 THEN 1 ELSE 0 END)
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND G.[G_L Account No_] NOT IN (N'30160', N'30161', N'30162', N'30163', N'30170')
  AND G.[Posting Date] >= @From AND G.[Posting Date] < @To
UNION ALL
SELECT N'UAE', N'Budget 3* (2026FSBUDJ)', SUM(B.[Amount]), NULL,
       SUM(CASE WHEN B.[Amount] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN B.[Amount] < 0 THEN 1 ELSE 0 END)
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B WITH (NOLOCK)
WHERE B.[Budget Name] = N'2026FSBUDJ' AND LEFT(B.[G_L Account No_], 1) = N'3'
  AND B.[Date] >= @From AND B.[Date] < @To
UNION ALL
SELECT N'KSA', N'Value Entry sale', SUM(VE.[Sales Amount (Actual)]), SUM(VE.[Item Ledger Entry Quantity]),
       SUM(CASE WHEN VE.[Sales Amount (Actual)] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN VE.[Sales Amount (Actual)] < 0 THEN 1 ELSE 0 END)
FROM BTL_LS_LIVE.dbo.[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
WHERE VE.[Item Ledger Entry Type] = 1 AND VE.[Posting Date] >= @From AND VE.[Posting Date] < @To
UNION ALL
SELECT N'KSA', N'G/L 3* excl. Other Income', SUM(G.[Amount]), NULL,
       SUM(CASE WHEN G.[Amount] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN G.[Amount] < 0 THEN 1 ELSE 0 END)
FROM BTL_LS_LIVE.dbo.[BATEEL-KSA$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND G.[G_L Account No_] NOT IN (N'30160', N'30161', N'30162', N'30163', N'30170')
  AND G.[Posting Date] >= @From AND G.[Posting Date] < @To
UNION ALL
SELECT N'FAKHRA', N'Value Entry sale', SUM(VE.[Sales Amount (Actual)]), SUM(VE.[Item Ledger Entry Quantity]),
       SUM(CASE WHEN VE.[Sales Amount (Actual)] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN VE.[Sales Amount (Actual)] < 0 THEN 1 ELSE 0 END)
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE WITH (NOLOCK)
WHERE VE.[Item Ledger Entry Type] = 1 AND VE.[Posting Date] >= @From AND VE.[Posting Date] < @To
UNION ALL
SELECT N'FAKHRA', N'G/L 3* excl. Other Income', SUM(G.[Amount]), NULL,
       SUM(CASE WHEN G.[Amount] > 0 THEN 1 ELSE 0 END), SUM(CASE WHEN G.[Amount] < 0 THEN 1 ELSE 0 END)
FROM FAKHRA_LIVE.dbo.[Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] G WITH (NOLOCK)
WHERE LEFT(G.[G_L Account No_], 1) = N'3' AND G.[G_L Account No_] NOT IN (N'30160', N'30161', N'30162', N'30163', N'30170')
  AND G.[Posting Date] >= @From AND G.[Posting Date] < @To;

-- Expected: Value Entry SumAmount > 0 and SumQty < 0; G/L and Budget SumAmount < 0.
-- Value Entry and |G/L| should be the same order of magnitude (G/L also holds
-- non-item revenue such as service charges, so it is usually somewhat larger).
