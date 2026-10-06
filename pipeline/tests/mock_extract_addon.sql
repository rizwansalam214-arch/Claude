/* Adds what channel_sku_extract.sql needs on top of tests/mock_sources.sql:
   UAE/KSA Dimension Value, G/L Account tables, Cost Amount column, dbo.V_Item,
   and last-year rows. Run after tests/mock_sources.sql, on a disposable server only. */
:on error exit
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'BTL_LS_LIVE.dbo.__mock_marker') IS NULL
BEGIN RAISERROR (N'Refusing to run: BTL_LS_LIVE is not the mock database.', 16, 1); SET NOEXEC ON; END;
GO
USE BTL_LS_LIVE;
GO
ALTER TABLE dbo.[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] ADD [Cost Amount (Actual)] DECIMAL(38,20) NOT NULL CONSTRAINT DF_uae_cost DEFAULT 0;
ALTER TABLE dbo.[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] ADD [Cost Amount (Actual)] DECIMAL(38,20) NOT NULL CONSTRAINT DF_ksa_cost DEFAULT 0;
CREATE TABLE dbo.[BATEEL-UAE$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] ([Dimension Code] NVARCHAR(20), [Code] NVARCHAR(20), [Name] NVARCHAR(100));
CREATE TABLE dbo.[BATEEL-UAE$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] ([No_] NVARCHAR(20), [Name] NVARCHAR(100));
CREATE TABLE dbo.[BATEEL-KSA$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] ([No_] NVARCHAR(20), [Name] NVARCHAR(100));
INSERT INTO dbo.[BATEEL-UAE$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES
    (N'DEPARTMENT', N'1001', N'Dubai Mall'), (N'CUSTOMER CATEGORY', N'1010', N'Airlines');
INSERT INTO dbo.[BATEEL-UAE$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES (N'30100', N'Sales'), (N'30160', N'Other income - rebates');
INSERT INTO dbo.[BATEEL-KSA$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES (N'30100', N'Sales');

-- Last-year rows (Sep 2025) so vs LY has something to compare
INSERT INTO dbo.[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [Item Ledger Entry Type], [Item No_], [Location Code], [Source Type], [Source No_],
     [Global Dimension 1 Code], [Global Dimension 2 Code], [Sales Amount (Actual)], [Item Ledger Entry Quantity])
VALUES ('2025-09-10', 1, N'ITM1', N'DXB1', 0, N'', N'', N'1001', 900, -9),
       ('2025-09-11', 1, N'ITM1', N'DXB1', 1, N'C001', N'1010', N'1001', 400, -4);
INSERT INTO dbo.[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [Item Ledger Entry Type], [Item No_], [Location Code], [Source Type], [Source No_],
     [Global Dimension 1 Code], [Global Dimension 2 Code], [Sales Amount (Actual)], [Item Ledger Entry Quantity])
VALUES ('2025-09-10', 1, N'ITM1', N'RUH1', 0, N'', N'', N'3001', 1100, -11);
GO
CREATE VIEW dbo.V_Item AS
    SELECT DISTINCT [No_], [Item Category Code] AS ItemCat, CAST(N'PG' AS NVARCHAR(20)) AS ProdGroup,
           CAST(NULL AS NVARCHAR(20)) AS ItemCat3, CAST(NULL AS NVARCHAR(20)) AS ItemCat4,
           CAST(NULL AS NVARCHAR(20)) AS [Retail Group 1], CAST(NULL AS NVARCHAR(20)) AS [Retail Group 2]
    FROM (SELECT [No_], [Item Category Code] FROM dbo.[BATEEL-UAE$Item$437dbf0e-84ff-417a-965d-ed2bb9650972]
          UNION SELECT [No_], [Item Category Code] FROM dbo.[BATEEL-KSA$Item$437dbf0e-84ff-417a-965d-ed2bb9650972]) X;
GO
USE FAKHRA_LIVE;
GO
ALTER TABLE dbo.[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] ADD [Cost Amount (Actual)] DECIMAL(38,20) NOT NULL CONSTRAINT DF_fak_cost DEFAULT 0;
CREATE TABLE dbo.[Al Fakhra Date$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] ([No_] NVARCHAR(20), [Name] NVARCHAR(100));
GO
