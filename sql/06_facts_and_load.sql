/* =============================================================================
   06 — Fact tables and nightly load
   The dashboard and the AI query these tables only, never the BC databases.
   rpt.usp_LoadSales reloads the full history window in one transaction, so a
   failed load leaves yesterday's data in place.
   ============================================================================= */

IF OBJECT_ID(N'rpt.FactSalesSku') IS NULL
CREATE TABLE rpt.FactSalesSku
(
    PostingDate      DATE            NOT NULL,
    Company          NVARCHAR(10)    NOT NULL,
    SegmentCode      NVARCHAR(20)    NOT NULL,
    SubLine          NVARCHAR(100)   NULL,
    SubLineSort      INT             NULL,
    CustCatCode      NVARCHAR(20)    NOT NULL,
    DeptCode         NVARCHAR(20)    NOT NULL,
    DeptName         NVARCHAR(100)   NOT NULL,
    DivisionId       NVARCHAR(50)    NULL,
    RuleId           INT             NULL,
    RuleType         NVARCHAR(10)    NULL,
    RuleStatus       NVARCHAR(12)    NULL,
    IsOverride       BIT             NOT NULL,
    LocationCode     NVARCHAR(20)    NOT NULL,
    CustomerNo       NVARCHAR(20)    NOT NULL,
    ItemNo           NVARCHAR(20)    NOT NULL,
    ItemDescription  NVARCHAR(100)   NOT NULL,
    ItemCategoryCode NVARCHAR(20)    NOT NULL,
    BaseUoM          NVARCHAR(10)    NOT NULL,
    Qty              DECIMAL(38, 10) NOT NULL,
    NetSalesLCY      DECIMAL(38, 10) NOT NULL,
    CurrencyCode     NVARCHAR(3)     NOT NULL,
    NetSalesAED      DECIMAL(38, 10) NOT NULL,
    LoadId           INT             NOT NULL
);

IF OBJECT_ID(N'rpt.FactSalesGL') IS NULL
CREATE TABLE rpt.FactSalesGL
(
    MonthStart   DATE            NOT NULL,
    Company      NVARCHAR(10)    NOT NULL,
    SegmentCode  NVARCHAR(20)    NOT NULL,
    SubLine      NVARCHAR(100)   NULL,
    SubLineSort  INT             NULL,
    CustCatCode  NVARCHAR(20)    NOT NULL,
    DeptCode     NVARCHAR(20)    NOT NULL,
    DeptName     NVARCHAR(100)   NOT NULL,
    DivisionId   NVARCHAR(50)    NULL,
    RuleId       INT             NULL,
    RuleType     NVARCHAR(10)    NULL,
    RuleStatus   NVARCHAR(12)    NULL,
    IsOverride   BIT             NOT NULL,
    GLAccountNo  NVARCHAR(20)    NOT NULL,
    LineType     NVARCHAR(12)    NOT NULL,   -- NET_SALES | OTHER_INCOME
    AmountLCY    DECIMAL(38, 10) NOT NULL,
    CurrencyCode NVARCHAR(3)     NOT NULL,
    AmountAED    DECIMAL(38, 10) NOT NULL,
    LoadId       INT             NOT NULL
);

IF OBJECT_ID(N'rpt.FactBudgetSales') IS NULL
CREATE TABLE rpt.FactBudgetSales
(
    MonthStart   DATE            NOT NULL,
    Company      NVARCHAR(10)    NOT NULL,
    BudgetName   NVARCHAR(50)    NOT NULL,
    SegmentCode  NVARCHAR(20)    NOT NULL,
    SubLine      NVARCHAR(100)   NULL,
    SubLineSort  INT             NULL,
    CustCatCode  NVARCHAR(20)    NOT NULL,
    DeptCode     NVARCHAR(20)    NOT NULL,
    DeptName     NVARCHAR(100)   NOT NULL,
    DivisionId   NVARCHAR(50)    NULL,
    RuleId       INT             NULL,
    RuleType     NVARCHAR(10)    NULL,
    RuleStatus   NVARCHAR(12)    NULL,
    IsOverride   BIT             NOT NULL,
    GLAccountNo  NVARCHAR(20)    NOT NULL,
    LineType     NVARCHAR(12)    NOT NULL,
    AmountLCY    DECIMAL(38, 10) NOT NULL,
    CurrencyCode NVARCHAR(3)     NOT NULL,
    AmountAED    DECIMAL(38, 10) NOT NULL,
    LoadId       INT             NOT NULL
);

IF OBJECT_ID(N'rpt.LoadLog') IS NULL
CREATE TABLE rpt.LoadLog
(
    LoadId         INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_rpt_LoadLog PRIMARY KEY,
    StartedAt      DATETIME2(0)   NOT NULL,
    FinishedAt     DATETIME2(0)   NULL,
    AsOfDate       DATE           NOT NULL,
    FromDate       DATE           NOT NULL,
    Status         NVARCHAR(10)   NOT NULL,   -- RUNNING | OK | FAILED
    RowsSalesSku   INT            NULL,
    RowsSalesGL    INT            NULL,
    RowsBudget     INT            NULL,
    ErrorMessage   NVARCHAR(4000) NULL
);
GO

CREATE OR ALTER PROCEDURE rpt.usp_LoadSales
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @AsOf DATE = ISNULL(@AsOfDate, CAST(GETDATE() AS DATE));
    DECLARE @HistoryMonths INT =
        (SELECT TRY_CONVERT(INT, SettingValue) FROM cfg.Setting WHERE SettingKey = N'HISTORY_MONTHS');

    IF @HistoryMonths IS NULL OR @HistoryMonths < 12
        THROW 50001, N'cfg.Setting HISTORY_MONTHS must be an integer >= 12.', 1;

    DECLARE @From DATE = DATEADD(MONTH, -@HistoryMonths, DATEFROMPARTS(YEAR(@AsOf), MONTH(@AsOf), 1));
    DECLARE @To   DATE = DATEADD(DAY, 1, @AsOf);
    DECLARE @LoadId INT;

    INSERT INTO rpt.LoadLog (StartedAt, AsOfDate, FromDate, Status)
    VALUES (SYSDATETIME(), @AsOf, @From, N'RUNNING');
    SET @LoadId = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE rpt.FactSalesSku;
        TRUNCATE TABLE rpt.FactSalesGL;
        TRUNCATE TABLE rpt.FactBudgetSales;

        INSERT INTO rpt.FactSalesSku
        (
            PostingDate, Company, SegmentCode, SubLine, SubLineSort, CustCatCode, DeptCode, DeptName, DivisionId,
            RuleId, RuleType, RuleStatus, IsOverride, LocationCode, CustomerNo, ItemNo, ItemDescription,
            ItemCategoryCode, BaseUoM, Qty, NetSalesLCY, CurrencyCode, NetSalesAED, LoadId
        )
        SELECT
            CAST(V.PostingDate AS DATE), V.Company, V.SegmentCode, V.SubLine, V.SubLineSort, V.CustCatCode, V.DeptCode,
            V.DeptName, V.DivisionId, V.RuleId, V.RuleType, V.RuleStatus, V.IsOverride, V.LocationCode, V.CustomerNo,
            V.ItemNo, V.ItemDescription, V.ItemCategoryCode, V.BaseUoM, V.Qty, V.NetSalesLCY, V.CurrencyCode,
            V.NetSalesAED, @LoadId
        FROM rpt.vSalesSku V
        WHERE V.PostingDate >= @From
          AND V.PostingDate <  @To;

        INSERT INTO rpt.FactSalesGL
        (
            MonthStart, Company, SegmentCode, SubLine, SubLineSort, CustCatCode, DeptCode, DeptName, DivisionId,
            RuleId, RuleType, RuleStatus, IsOverride, GLAccountNo, LineType, AmountLCY, CurrencyCode, AmountAED, LoadId
        )
        SELECT
            V.MonthStart, V.Company, V.SegmentCode, V.SubLine, V.SubLineSort, V.CustCatCode, V.DeptCode, V.DeptName,
            V.DivisionId, V.RuleId, V.RuleType, V.RuleStatus, V.IsOverride, V.GLAccountNo, V.LineType, V.AmountLCY,
            V.CurrencyCode, V.AmountAED, @LoadId
        FROM rpt.vSalesGL V
        WHERE V.MonthStart >= @From
          AND V.MonthStart <  @To;

        -- Budget: every active version, full year (no cut-off at today).
        INSERT INTO rpt.FactBudgetSales
        (
            MonthStart, Company, BudgetName, SegmentCode, SubLine, SubLineSort, CustCatCode, DeptCode, DeptName,
            DivisionId, RuleId, RuleType, RuleStatus, IsOverride, GLAccountNo, LineType, AmountLCY, CurrencyCode,
            AmountAED, LoadId
        )
        SELECT
            V.MonthStart, V.Company, V.BudgetName, V.SegmentCode, V.SubLine, V.SubLineSort, V.CustCatCode, V.DeptCode,
            V.DeptName, V.DivisionId, V.RuleId, V.RuleType, V.RuleStatus, V.IsOverride, V.GLAccountNo, V.LineType,
            V.AmountLCY, V.CurrencyCode, V.AmountAED, @LoadId
        FROM rpt.vBudgetSales V;

        COMMIT TRANSACTION;

        UPDATE rpt.LoadLog
        SET FinishedAt   = SYSDATETIME(),
            Status       = N'OK',
            RowsSalesSku = (SELECT COUNT(*) FROM rpt.FactSalesSku),
            RowsSalesGL  = (SELECT COUNT(*) FROM rpt.FactSalesGL),
            RowsBudget   = (SELECT COUNT(*) FROM rpt.FactBudgetSales)
        WHERE LoadId = @LoadId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;

        UPDATE rpt.LoadLog
        SET FinishedAt = SYSDATETIME(), Status = N'FAILED', ErrorMessage = ERROR_MESSAGE()
        WHERE LoadId = @LoadId;

        THROW;
    END CATCH;
END;
GO

/* Monthly budget spread evenly over calendar days, so MTD actuals can be
   compared with MTD budget instead of a full month.
   OPEN DECISION: calendar days (this view) vs trading days vs full month only. */
CREATE OR ALTER VIEW rpt.vBudgetSalesDaily
AS
    SELECT
        D.BudgetDate,
        B.MonthStart,
        B.Company,
        B.BudgetName,
        B.SegmentCode,
        B.SubLine,
        B.SubLineSort,
        B.CustCatCode,
        B.DeptCode,
        B.DeptName,
        B.GLAccountNo,
        B.LineType,
        B.AmountLCY / DAY(EOMONTH(B.MonthStart)) AS AmountLCY,
        B.CurrencyCode,
        B.AmountAED / DAY(EOMONTH(B.MonthStart)) AS AmountAED
    FROM rpt.FactBudgetSales B
    CROSS APPLY
    (
        SELECT TOP (DAY(EOMONTH(B.MonthStart)))
            DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, B.MonthStart) AS BudgetDate
        FROM sys.all_objects
    ) D;
GO
