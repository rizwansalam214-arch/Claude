/* =============================================================================
   05 — Source views (sales only)
   Read the BC tables through src.* synonyms, apply one sign convention, one
   segment resolution and one FX rate. The load procedure materialises them.

   Sign convention (all facts positive for normal activity):
     Value Entry   NetSales = +[Sales Amount (Actual)]   (BC stores sales positive)
                   Qty      = -[Item Ledger Entry Quantity] (BC stores sales negative)
     G/L Entry     Amount   = -[Amount] on 3* accounts    (revenue is a credit)
     G/L Budget    Amount   = -[Amount] on 3* accounts    (same as G/L)
   Verify on live data with diagnostics/01_sign_check.sql.

   Key per company:
     UAE / KSA  CustCatCode = Global Dimension 1, DeptCode = Global Dimension 2
     FAKHRA     CustCatCode = '' (none),          DeptCode = Global Dimension 1
   ============================================================================= */

/* Al Fakhra department names, from the dimension that IS Global Dimension 1
   (the old extracts took TOP 1 across every dimension sharing the code). */
CREATE OR ALTER VIEW rpt.vFakhraDepartment
AS
    SELECT
        LTRIM(RTRIM(DV.[Code])) COLLATE DATABASE_DEFAULT AS DeptCode,
        DV.[Name]               COLLATE DATABASE_DEFAULT AS DeptName
    FROM src.FAKHRA_DimensionValue DV
    INNER JOIN src.FAKHRA_GLSetup GS
        ON GS.[Global Dimension 1 Code] = DV.[Dimension Code];
GO

/* ---------------------------------------------------------------------------
   SKU basis: Value Entry, sale entries only (Item Ledger Entry Type 1).
   Grain: day x company x cust cat x dept x location x customer x item.
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW rpt.vSalesSku
AS
WITH S AS
(
    SELECT
        N'UAE' AS Company,
        VE.[Posting Date] AS PostingDate,
        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT AS CustCatCode,
        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT AS DeptCode,
        ISNULL(VE.[Location Code], N'') COLLATE DATABASE_DEFAULT AS LocationCode,
        CASE WHEN VE.[Source Type] = 1 THEN VE.[Source No_] ELSE N'' END COLLATE DATABASE_DEFAULT AS CustomerNo,
        VE.[Item No_] COLLATE DATABASE_DEFAULT AS ItemNo,
        ISNULL(I.[Description], N'') COLLATE DATABASE_DEFAULT AS ItemDescription,
        ISNULL(I.[Item Category Code], N'') COLLATE DATABASE_DEFAULT AS ItemCategoryCode,
        ISNULL(I.[Base Unit of Measure], N'') COLLATE DATABASE_DEFAULT AS BaseUoM,
        SUM(VE.[Sales Amount (Actual)]) AS NetSalesLCY,
        SUM(-VE.[Item Ledger Entry Quantity]) AS Qty
    FROM src.UAE_ValueEntry VE
    LEFT JOIN src.UAE_Item I ON I.[No_] = VE.[Item No_]
    WHERE VE.[Item Ledger Entry Type] = 1
    GROUP BY VE.[Posting Date], VE.[Global Dimension 1 Code], VE.[Global Dimension 2 Code], VE.[Location Code],
             VE.[Source Type], VE.[Source No_], VE.[Item No_], I.[Description], I.[Item Category Code], I.[Base Unit of Measure]

    UNION ALL

    SELECT
        N'KSA',
        VE.[Posting Date],
        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT,
        ISNULL(VE.[Location Code], N'') COLLATE DATABASE_DEFAULT,
        CASE WHEN VE.[Source Type] = 1 THEN VE.[Source No_] ELSE N'' END COLLATE DATABASE_DEFAULT,
        VE.[Item No_] COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Description], N'') COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Item Category Code], N'') COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Base Unit of Measure], N'') COLLATE DATABASE_DEFAULT,
        SUM(VE.[Sales Amount (Actual)]),
        SUM(-VE.[Item Ledger Entry Quantity])
    FROM src.KSA_ValueEntry VE
    LEFT JOIN src.KSA_Item I ON I.[No_] = VE.[Item No_]
    WHERE VE.[Item Ledger Entry Type] = 1
    GROUP BY VE.[Posting Date], VE.[Global Dimension 1 Code], VE.[Global Dimension 2 Code], VE.[Location Code],
             VE.[Source Type], VE.[Source No_], VE.[Item No_], I.[Description], I.[Item Category Code], I.[Base Unit of Measure]

    UNION ALL

    SELECT
        N'FAKHRA',
        VE.[Posting Date],
        CAST(N'' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        ISNULL(VE.[Location Code], N'') COLLATE DATABASE_DEFAULT,
        CASE WHEN VE.[Source Type] = 1 THEN VE.[Source No_] ELSE N'' END COLLATE DATABASE_DEFAULT,
        VE.[Item No_] COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Description], N'') COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Item Category Code], N'') COLLATE DATABASE_DEFAULT,
        ISNULL(I.[Base Unit of Measure], N'') COLLATE DATABASE_DEFAULT,
        SUM(VE.[Sales Amount (Actual)]),
        SUM(-VE.[Item Ledger Entry Quantity])
    FROM src.FAKHRA_ValueEntry VE
    LEFT JOIN src.FAKHRA_Item I ON I.[No_] = VE.[Item No_]
    WHERE VE.[Item Ledger Entry Type] = 1
    GROUP BY VE.[Posting Date], VE.[Global Dimension 1 Code], VE.[Location Code],
             VE.[Source Type], VE.[Source No_], VE.[Item No_], I.[Description], I.[Item Category Code], I.[Base Unit of Measure]
)
SELECT
    S.Company,
    S.PostingDate,
    S.CustCatCode,
    S.DeptCode,
    COALESCE(D.DepartmentDesc, FD.DeptName, N'') AS DeptName,
    D.DivisionId,
    ISNULL(R.SegmentCode, N'UNASSIGNED') AS SegmentCode,
    R.SubLine,
    R.SubLineSort,
    R.RuleId,
    R.RuleType,
    R.RuleStatus,
    ISNULL(R.IsOverride, 0) AS IsOverride,
    S.LocationCode,
    S.CustomerNo,
    S.ItemNo,
    S.ItemDescription,
    S.ItemCategoryCode,
    S.BaseUoM,
    S.Qty,
    S.NetSalesLCY,
    C.CurrencyCode,
    S.NetSalesLCY * FX.RateToAED AS NetSalesAED
FROM S
INNER JOIN cfg.Company C ON C.Company = S.Company
INNER JOIN cfg.FxRate FX ON FX.CurrencyCode = C.CurrencyCode
OUTER APPLY rpt.fnDivision(CASE WHEN S.Company IN (N'UAE', N'KSA') THEN S.DeptCode END) D
LEFT JOIN rpt.vFakhraDepartment FD ON S.Company = N'FAKHRA' AND FD.DeptCode = S.DeptCode
OUTER APPLY rpt.fnResolveSegment(S.Company, S.CustCatCode, S.DeptCode, D.DivisionId) R;
GO

/* ---------------------------------------------------------------------------
   P&L basis: G/L Entry, 3* accounts, month grain.
   - Other Income (cfg.OtherIncomeAccount) is LineType OTHER_INCOME, never
     NET_SALES (fixes the Summary double count).
   - Closing-date entries (BC stores them at 23:59:59) are excluded, otherwise
     year-end close wipes December once history spans a year end.
   - Nothing is dropped: unmapped rows land in UNASSIGNED so totals tie to TB.
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW rpt.vSalesGL
AS
WITH S AS
(
    SELECT
        N'UAE' AS Company,
        DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1) AS MonthStart,
        LTRIM(RTRIM(ISNULL(G.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT AS CustCatCode,
        LTRIM(RTRIM(ISNULL(G.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT AS DeptCode,
        G.[G_L Account No_] COLLATE DATABASE_DEFAULT AS GLAccountNo,
        SUM(-G.[Amount]) AS AmountLCY
    FROM src.UAE_GLEntry G
    WHERE LEFT(G.[G_L Account No_], 1) = N'3'
      AND CONVERT(TIME(0), G.[Posting Date]) <> '23:59:59'
    GROUP BY DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1),
             G.[Global Dimension 1 Code], G.[Global Dimension 2 Code], G.[G_L Account No_]

    UNION ALL

    SELECT
        N'KSA',
        DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1),
        LTRIM(RTRIM(ISNULL(G.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(G.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT,
        G.[G_L Account No_] COLLATE DATABASE_DEFAULT,
        SUM(-G.[Amount])
    FROM src.KSA_GLEntry G
    WHERE LEFT(G.[G_L Account No_], 1) = N'3'
      AND CONVERT(TIME(0), G.[Posting Date]) <> '23:59:59'
    GROUP BY DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1),
             G.[Global Dimension 1 Code], G.[Global Dimension 2 Code], G.[G_L Account No_]

    UNION ALL

    SELECT
        N'FAKHRA',
        DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1),
        CAST(N'' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(G.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        G.[G_L Account No_] COLLATE DATABASE_DEFAULT,
        SUM(-G.[Amount])
    FROM src.FAKHRA_GLEntry G
    WHERE LEFT(G.[G_L Account No_], 1) = N'3'
      AND CONVERT(TIME(0), G.[Posting Date]) <> '23:59:59'
    GROUP BY DATEFROMPARTS(YEAR(G.[Posting Date]), MONTH(G.[Posting Date]), 1),
             G.[Global Dimension 1 Code], G.[G_L Account No_]
)
SELECT
    S.Company,
    S.MonthStart,
    S.CustCatCode,
    S.DeptCode,
    COALESCE(D.DepartmentDesc, FD.DeptName, N'') AS DeptName,
    D.DivisionId,
    ISNULL(R.SegmentCode, N'UNASSIGNED') AS SegmentCode,
    R.SubLine,
    R.SubLineSort,
    R.RuleId,
    R.RuleType,
    R.RuleStatus,
    ISNULL(R.IsOverride, 0) AS IsOverride,
    S.GLAccountNo,
    CASE WHEN OI.GLAccountNo IS NULL THEN N'NET_SALES' ELSE N'OTHER_INCOME' END AS LineType,
    S.AmountLCY,
    C.CurrencyCode,
    S.AmountLCY * FX.RateToAED AS AmountAED
FROM S
INNER JOIN cfg.Company C ON C.Company = S.Company
INNER JOIN cfg.FxRate FX ON FX.CurrencyCode = C.CurrencyCode
LEFT JOIN cfg.OtherIncomeAccount OI ON OI.GLAccountNo = S.GLAccountNo
OUTER APPLY rpt.fnDivision(CASE WHEN S.Company IN (N'UAE', N'KSA') THEN S.DeptCode END) D
LEFT JOIN rpt.vFakhraDepartment FD ON S.Company = N'FAKHRA' AND FD.DeptCode = S.DeptCode
OUTER APPLY rpt.fnResolveSegment(S.Company, S.CustCatCode, S.DeptCode, D.DivisionId) R;
GO

/* ---------------------------------------------------------------------------
   Budget: G/L Budget Entry, 3* accounts, month grain, active budget versions
   only (cfg.BudgetVersion). Same keys, same resolver and same sign as actuals,
   so budget and actual rows carry identical segment, sub-line and department
   (fixes: budget sign, division-label mismatch, cust-cat department key,
   UAE budget double count, Other Income inside sales budget).
   --------------------------------------------------------------------------- */
CREATE OR ALTER VIEW rpt.vBudgetSales
AS
WITH S AS
(
    SELECT
        N'UAE' AS Company,
        B.[Budget Name] COLLATE DATABASE_DEFAULT AS BudgetName,
        DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1) AS MonthStart,
        LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT AS CustCatCode,
        LTRIM(RTRIM(ISNULL(B.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT AS DeptCode,
        B.[G_L Account No_] COLLATE DATABASE_DEFAULT AS GLAccountNo,
        SUM(-B.[Amount]) AS AmountLCY
    FROM src.UAE_GLBudgetEntry B
    WHERE LEFT(B.[G_L Account No_], 1) = N'3'
    GROUP BY B.[Budget Name], DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1),
             B.[Global Dimension 1 Code], B.[Global Dimension 2 Code], B.[G_L Account No_]

    UNION ALL

    SELECT
        N'KSA',
        B.[Budget Name] COLLATE DATABASE_DEFAULT,
        DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1),
        LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(B.[Global Dimension 2 Code], N''))) COLLATE DATABASE_DEFAULT,
        B.[G_L Account No_] COLLATE DATABASE_DEFAULT,
        SUM(-B.[Amount])
    FROM src.KSA_GLBudgetEntry B
    WHERE LEFT(B.[G_L Account No_], 1) = N'3'
    GROUP BY B.[Budget Name], DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1),
             B.[Global Dimension 1 Code], B.[Global Dimension 2 Code], B.[G_L Account No_]

    UNION ALL

    SELECT
        N'FAKHRA',
        B.[Budget Name] COLLATE DATABASE_DEFAULT,
        DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1),
        CAST(N'' AS NVARCHAR(20)) COLLATE DATABASE_DEFAULT,
        LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], N''))) COLLATE DATABASE_DEFAULT,
        B.[G_L Account No_] COLLATE DATABASE_DEFAULT,
        SUM(-B.[Amount])
    FROM src.FAKHRA_GLBudgetEntry B
    WHERE LEFT(B.[G_L Account No_], 1) = N'3'
    GROUP BY B.[Budget Name], DATEFROMPARTS(YEAR(B.[Date]), MONTH(B.[Date]), 1),
             B.[Global Dimension 1 Code], B.[G_L Account No_]
)
SELECT
    S.Company,
    S.BudgetName,
    S.MonthStart,
    S.CustCatCode,
    S.DeptCode,
    COALESCE(D.DepartmentDesc, FD.DeptName, N'') AS DeptName,
    D.DivisionId,
    ISNULL(R.SegmentCode, N'UNASSIGNED') AS SegmentCode,
    R.SubLine,
    R.SubLineSort,
    R.RuleId,
    R.RuleType,
    R.RuleStatus,
    ISNULL(R.IsOverride, 0) AS IsOverride,
    S.GLAccountNo,
    CASE WHEN OI.GLAccountNo IS NULL THEN N'NET_SALES' ELSE N'OTHER_INCOME' END AS LineType,
    S.AmountLCY,
    C.CurrencyCode,
    S.AmountLCY * FX.RateToAED AS AmountAED
FROM S
INNER JOIN cfg.BudgetVersion BV
    ON BV.Company = S.Company
   AND BV.FiscalYear = YEAR(S.MonthStart)
   AND BV.BudgetName = S.BudgetName
   AND BV.IsActive = 1
INNER JOIN cfg.Company C ON C.Company = S.Company
INNER JOIN cfg.FxRate FX ON FX.CurrencyCode = C.CurrencyCode
LEFT JOIN cfg.OtherIncomeAccount OI ON OI.GLAccountNo = S.GLAccountNo
OUTER APPLY rpt.fnDivision(CASE WHEN S.Company IN (N'UAE', N'KSA') THEN S.DeptCode END) D
LEFT JOIN rpt.vFakhraDepartment FD ON S.Company = N'FAKHRA' AND FD.DeptCode = S.DeptCode
OUTER APPLY rpt.fnResolveSegment(S.Company, S.CustCatCode, S.DeptCode, D.DivisionId) R;
GO
