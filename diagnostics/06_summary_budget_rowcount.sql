/* =============================================================================
   DIAGNOSTIC 06 — Is the Summary budget really zero in SQL? (read-only)
   -----------------------------------------------------------------------------
   The KSA budget block in summary_gl_extract.sql has NO division or customer
   category filter: only budget name, date and account. The Detail extract's
   KSA block reads the same table with the same name and dates and returns
   318 rows. So if the count below is > 0, the Summary SQL is returning budget
   rows and they are being lost downstream (renderer / merge step), not in SQL.

   Also note: Summary takes budget as +[Amount] (so Sales Budget is NEGATIVE)
   while Detail takes -[Amount]. A renderer that drops or nets negative
   values, or matches Summary rows to Detail labels, would show zero.
   ============================================================================= */

DECLARE @FromDate   DATE         = DATEFROMPARTS(YEAR(GETDATE()), 1, 1);
DECLARE @ToDate     DATE         = CAST(GETDATE() AS DATE);
DECLARE @BudgetName NVARCHAR(50) = N'2026FSBUDJ';

-- Exact predicates of the Summary "KSA BUDGET - DIVISION" block (sales accounts only)
SELECT
    COUNT(*)       AS KsaBudgetRows_SummaryPredicates,
    SUM(B.[Amount]) AS SummarySign_SalesBudget,    -- what Summary outputs (expect negative)
    SUM(-B.[Amount]) AS CorrectSign_SalesBudget
FROM BTL_LS_LIVE.dbo.[BATEEL-KSA$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B WITH (NOLOCK)
WHERE B.[Budget Name] = @BudgetName
  AND B.[Date] >= @FromDate
  AND B.[Date] <  DATEADD(DAY, 1, @ToDate)
  AND LEFT(B.[G_L Account No_], 1) = N'3';

-- Same for the UAE division block (uses upper-case Division_IDs, as Summary does)
SELECT
    COUNT(*)       AS UaeDivisionBudgetRows_SummaryPredicates,
    SUM(B.[Amount]) AS SummarySign_SalesBudget
FROM BTL_LS_LIVE.dbo.[BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B WITH (NOLOCK)
LEFT JOIN BTL_LS_LIVE.dbo.Jedoxdept JD WITH (NOLOCK)
    ON TRY_CONVERT(INT, B.[Global Dimension 2 Code]) = TRY_CONVERT(INT, JD.[Navision_ID])
WHERE B.[Budget Name] = @BudgetName
  AND B.[Date] >= @FromDate
  AND B.[Date] <  DATEADD(DAY, 1, @ToDate)
  AND LEFT(B.[G_L Account No_], 1) = N'3'
  AND JD.[Division_ID] IN (N'CAFE', N'E-COMMERCE', N'ECOM', N'ECOMMERCE', N'ELAN',
                           N'FRANCHISE', N'FRANCHAISE', N'RETAIL', N'SNS');
