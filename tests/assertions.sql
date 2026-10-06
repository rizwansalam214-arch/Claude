/* =============================================================================
   Assertions against the mock sources (tests/mock_sources.sql).
   Run in BATEEL_RPT after deploying sql/ and running the load as of 2026-10-05.
   Fails with error 50000 if any check fails.
   ============================================================================= */

SET NOCOUNT ON;

DECLARE @r TABLE (Test NVARCHAR(200), Expected DECIMAL(38, 6), Actual DECIMAL(38, 6));

INSERT INTO @r SELECT N'01 UAE SKU net sales are positive and complete in window', 2050,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'UAE');
INSERT INTO @r SELECT N'02 Airline sale counted in AIRLINES', 500,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'UAE' AND SegmentCode = N'AIRLINES');
INSERT INTO @r SELECT N'03 ...and not also in RETAIL (no double count)', 1000,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'UAE' AND SegmentCode = N'RETAIL');
INSERT INTO @r SELECT N'04 Override flagged on the airline row', 1,
    (SELECT COUNT(*) FROM rpt.FactSalesSku WHERE CustCatCode = N'1010' AND IsOverride = 1);
INSERT INTO @r SELECT N'05 Mixed-case Jedoxdept Franchise resolves', 200,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE SegmentCode = N'FRANCHISE');
INSERT INTO @r SELECT N'06 Dept 1196 goes to ECOM over Jedoxdept RETAIL', 300,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'UAE' AND SegmentCode = N'ECOM');
INSERT INTO @r SELECT N'07 Quantity is positive for sales', 10,
    (SELECT SUM(Qty) FROM rpt.FactSalesSku WHERE Company = N'UAE' AND SegmentCode = N'RETAIL');
INSERT INTO @r SELECT N'08 Rows before the 24-month window excluded', 0,
    (SELECT COUNT(*) FROM rpt.FactSalesSku WHERE PostingDate < '2024-10-01');
INSERT INTO @r SELECT N'09 KSA SAR converted to AED at 0.979333', 979.333,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'KSA' AND SegmentCode = N'RETAIL');
INSERT INTO @r SELECT N'10 KSA dept 3193 goes to B2B', 97.9333,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'KSA' AND SegmentCode = N'B2B');
INSERT INTO @r SELECT N'11 Fakhra padded code 017 trimmed -> KSA Private Label', 29.37999,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE SubLine = N'KSA Private Label');
INSERT INTO @r SELECT N'12 Fakhra unmapped code kept as UNASSIGNED', 68.55331,
    (SELECT SUM(NetSalesAED) FROM rpt.FactSalesSku WHERE Company = N'FAKHRA' AND SegmentCode = N'UNASSIGNED');
INSERT INTO @r SELECT N'13 Fakhra dept name from the GD1 dimension only', 1,
    (SELECT COUNT(*) FROM rpt.FactSalesSku WHERE Company = N'FAKHRA' AND DeptCode = N'014' AND DeptName = N'Jomara Distribution KSA');
INSERT INTO @r SELECT N'14 UAE unassigned dept visible on DQ', 50,
    (SELECT SUM(AmountAED) FROM rpt.dqUnassigned WHERE Basis = N'SKU' AND Company = N'UAE');

INSERT INTO @r SELECT N'15 P&L RETAIL Sep net sales positive, excl. Other Income', 1500,
    (SELECT SUM(AmountAED) FROM rpt.FactSalesGL WHERE Company = N'UAE' AND SegmentCode = N'RETAIL'
       AND MonthStart = '2026-09-01' AND LineType = N'NET_SALES');
INSERT INTO @r SELECT N'16 Other Income on its own line', 80,
    (SELECT SUM(AmountAED) FROM rpt.FactSalesGL WHERE LineType = N'OTHER_INCOME');
INSERT INTO @r SELECT N'17 Closing entry excluded: Dec 2025 intact', 1500,
    (SELECT SUM(AmountAED) FROM rpt.FactSalesGL WHERE Company = N'UAE' AND MonthStart = '2025-12-01');
INSERT INTO @r SELECT N'18 P&L airline counted once', 500,
    (SELECT SUM(AmountAED) FROM rpt.FactSalesGL WHERE Company = N'UAE' AND SegmentCode = N'AIRLINES');

INSERT INTO @r SELECT N'19 Budget RETAIL Sep positive', 2000,
    (SELECT SUM(AmountAED) FROM rpt.FactBudgetSales WHERE Company = N'UAE' AND SegmentCode = N'RETAIL'
       AND MonthStart = '2026-09-01' AND LineType = N'NET_SALES');
INSERT INTO @r SELECT N'20 Cust-cat budget keeps the real dept key', 600,
    (SELECT SUM(AmountAED) FROM rpt.FactBudgetSales WHERE SegmentCode = N'AIRLINES' AND DeptCode = N'1001');
INSERT INTO @r SELECT N'21 Inactive budget name excluded; Other Income outside Net Sales', 2600,
    (SELECT SUM(AmountAED) FROM rpt.FactBudgetSales WHERE Company = N'UAE' AND MonthStart = '2026-09-01' AND LineType = N'NET_SALES');
INSERT INTO @r SELECT N'22 Future budget months loaded (no cut-off at today)', 2400,
    (SELECT SUM(AmountAED) FROM rpt.FactBudgetSales WHERE MonthStart = '2026-12-01');
INSERT INTO @r SELECT N'23 Wrong Fakhra budget name shows as 0 rows', 0,
    (SELECT Rows FROM rpt.dqBudgetCoverage WHERE Company = N'FAKHRA');
INSERT INTO @r SELECT N'24 Daily budget sums back to month', 2000,
    (SELECT SUM(AmountAED) FROM rpt.vBudgetSalesDaily WHERE Company = N'UAE' AND SegmentCode = N'RETAIL'
       AND LineType = N'NET_SALES' AND MonthStart = '2026-09-01');
INSERT INTO @r SELECT N'25 MTD budget to 15 Sep = half', 1000,
    (SELECT SUM(AmountAED) FROM rpt.vBudgetSalesDaily WHERE Company = N'UAE' AND SegmentCode = N'RETAIL'
       AND LineType = N'NET_SALES' AND BudgetDate <= '2026-09-15' AND MonthStart = '2026-09-01');

INSERT INTO @r SELECT N'26 SKU -> P&L bridge difference (RETAIL Sep)', 500,
    (SELECT DifferenceAED FROM rpt.dqSkuToPLBridge WHERE Company = N'UAE' AND SegmentCode = N'RETAIL' AND MonthStart = '2026-09-01');
INSERT INTO @r SELECT N'27 Provisional rule amounts surfaced (017)', 29.37999,
    (SELECT SkuAmountAED FROM rpt.dqProvisionalMapping WHERE Company = N'FAKHRA' AND MatchCode = N'017');
INSERT INTO @r SELECT N'28 Load logged OK', 1,
    (SELECT COUNT(*) FROM rpt.dqLastLoad WHERE Status = N'OK');

SELECT CASE WHEN ABS(ISNULL(Actual, -999999) - Expected) < 0.0001 THEN N'PASS' ELSE N'FAIL' END AS Result,
       Test, Expected, Actual
FROM @r
ORDER BY Test;

IF EXISTS (SELECT 1 FROM @r WHERE ABS(ISNULL(Actual, -999999) - Expected) >= 0.0001)
    THROW 50000, N'One or more assertions failed.', 1;
