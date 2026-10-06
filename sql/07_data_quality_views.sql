/* =============================================================================
   07 — Data quality views (feed the Data Quality page)
   ============================================================================= */

/* Freshness: latest load and its status. */
CREATE OR ALTER VIEW rpt.dqLastLoad
AS
    SELECT TOP (1) L.*
    FROM rpt.LoadLog L
    ORDER BY L.LoadId DESC;
GO

/* Anything no rule claims. Must be zero or explained before go-live. */
CREATE OR ALTER VIEW rpt.dqUnassigned
AS
    SELECT N'SKU' AS Basis, F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId,
           COUNT(*) AS Rows, SUM(F.NetSalesAED) AS AmountAED
    FROM rpt.FactSalesSku F
    WHERE F.SegmentCode = N'UNASSIGNED'
    GROUP BY F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId

    UNION ALL

    SELECT N'P&L', F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId,
           COUNT(*), SUM(F.AmountAED)
    FROM rpt.FactSalesGL F
    WHERE F.SegmentCode = N'UNASSIGNED' AND F.LineType = N'NET_SALES'
    GROUP BY F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId

    UNION ALL

    SELECT N'BUDGET', F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId,
           COUNT(*), SUM(F.AmountAED)
    FROM rpt.FactBudgetSales F
    WHERE F.SegmentCode = N'UNASSIGNED' AND F.LineType = N'NET_SALES'
    GROUP BY F.Company, F.CustCatCode, F.DeptCode, F.DeptName, F.DivisionId;
GO

/* Department codes that Jedoxdept does not know (UAE / KSA). */
CREATE OR ALTER VIEW rpt.dqUnresolvedDepartment
AS
    SELECT Company, DeptCode, SUM(AmountAED) AS AmountAED
    FROM
    (
        SELECT Company, DeptCode, NetSalesAED AS AmountAED FROM rpt.FactSalesSku
        WHERE Company IN (N'UAE', N'KSA') AND DivisionId IS NULL
        UNION ALL
        SELECT Company, DeptCode, AmountAED FROM rpt.FactSalesGL
        WHERE Company IN (N'UAE', N'KSA') AND DivisionId IS NULL AND LineType = N'NET_SALES'
    ) X
    GROUP BY Company, DeptCode;
GO

/* Rows where precedence decided the segment: a lower-priority rule would
   have put them elsewhere. This is the volume the old extracts double-counted. */
CREATE OR ALTER VIEW rpt.dqPrecedenceOverride
AS
    SELECT N'SKU' AS Basis, F.Company, F.SegmentCode, F.RuleType, F.CustCatCode, F.DeptCode, F.DivisionId,
           SUM(F.NetSalesAED) AS AmountAED
    FROM rpt.FactSalesSku F
    WHERE F.IsOverride = 1
    GROUP BY F.Company, F.SegmentCode, F.RuleType, F.CustCatCode, F.DeptCode, F.DivisionId

    UNION ALL

    SELECT N'P&L', F.Company, F.SegmentCode, F.RuleType, F.CustCatCode, F.DeptCode, F.DivisionId,
           SUM(F.AmountAED)
    FROM rpt.FactSalesGL F
    WHERE F.IsOverride = 1 AND F.LineType = N'NET_SALES'
    GROUP BY F.Company, F.SegmentCode, F.RuleType, F.CustCatCode, F.DeptCode, F.DivisionId;
GO

/* Amounts flowing through rules still marked PROVISIONAL (1181, 017, SNS). */
CREATE OR ALTER VIEW rpt.dqProvisionalMapping
AS
    SELECT R.RuleId, R.Company, R.RuleType, R.MatchCode, R.SegmentCode, R.SubLine, R.Note,
           ISNULL(S.AmountAED, 0) AS SkuAmountAED,
           ISNULL(G.AmountAED, 0) AS PLAmountAED,
           ISNULL(B.AmountAED, 0) AS BudgetAmountAED
    FROM cfg.SegmentRule R
    LEFT JOIN (SELECT RuleId, SUM(NetSalesAED) AS AmountAED FROM rpt.FactSalesSku GROUP BY RuleId) S
        ON S.RuleId = R.RuleId
    LEFT JOIN (SELECT RuleId, SUM(AmountAED) AS AmountAED FROM rpt.FactSalesGL WHERE LineType = N'NET_SALES' GROUP BY RuleId) G
        ON G.RuleId = R.RuleId
    LEFT JOIN (SELECT RuleId, SUM(AmountAED) AS AmountAED FROM rpt.FactBudgetSales WHERE LineType = N'NET_SALES' GROUP BY RuleId) B
        ON B.RuleId = R.RuleId
    WHERE R.IsActive = 1 AND R.Status = N'PROVISIONAL';
GO

/* Budget versions that loaded nothing (catches a wrong budget name, e.g. Fakhra). */
CREATE OR ALTER VIEW rpt.dqBudgetCoverage
AS
    SELECT BV.Company, BV.FiscalYear, BV.BudgetName, BV.Status,
           COUNT(F.MonthStart) AS Rows,
           COUNT(DISTINCT F.MonthStart) AS MonthsLoaded,
           ISNULL(SUM(CASE WHEN F.LineType = N'NET_SALES' THEN F.AmountAED END), 0) AS NetSalesBudgetAED
    FROM cfg.BudgetVersion BV
    LEFT JOIN rpt.FactBudgetSales F
        ON F.Company = BV.Company
       AND F.BudgetName = BV.BudgetName
       AND YEAR(F.MonthStart) = BV.FiscalYear
    WHERE BV.IsActive = 1
    GROUP BY BV.Company, BV.FiscalYear, BV.BudgetName, BV.Status;
GO

/* SKU basis -> P&L basis bridge per month, company and segment.
   The two will not tie by design (non-item revenue, timing); this shows by how much. */
CREATE OR ALTER VIEW rpt.dqSkuToPLBridge
AS
    WITH Sku AS
    (
        SELECT DATEFROMPARTS(YEAR(PostingDate), MONTH(PostingDate), 1) AS MonthStart,
               Company, SegmentCode, SUM(NetSalesAED) AS SkuNetSalesAED
        FROM rpt.FactSalesSku
        GROUP BY DATEFROMPARTS(YEAR(PostingDate), MONTH(PostingDate), 1), Company, SegmentCode
    ),
    PL AS
    (
        SELECT MonthStart, Company, SegmentCode, SUM(AmountAED) AS PLNetSalesAED
        FROM rpt.FactSalesGL
        WHERE LineType = N'NET_SALES'
        GROUP BY MonthStart, Company, SegmentCode
    )
    SELECT
        COALESCE(S.MonthStart, P.MonthStart)   AS MonthStart,
        COALESCE(S.Company, P.Company)         AS Company,
        COALESCE(S.SegmentCode, P.SegmentCode) AS SegmentCode,
        ISNULL(S.SkuNetSalesAED, 0)            AS SkuNetSalesAED,
        ISNULL(P.PLNetSalesAED, 0)             AS PLNetSalesAED,
        ISNULL(P.PLNetSalesAED, 0) - ISNULL(S.SkuNetSalesAED, 0) AS DifferenceAED,
        CASE WHEN ISNULL(P.PLNetSalesAED, 0) = 0 THEN NULL
             ELSE (ISNULL(P.PLNetSalesAED, 0) - ISNULL(S.SkuNetSalesAED, 0)) / P.PLNetSalesAED END AS DifferencePct
    FROM Sku S
    FULL OUTER JOIN PL P
        ON P.MonthStart = S.MonthStart
       AND P.Company = S.Company
       AND P.SegmentCode = S.SegmentCode;
GO
