/* =============================================================================
   Mock BC source databases for testing the semantic layer locally.
   Same database, table and column names as production; minimal columns.
   Sources use a case-sensitive collation (as BC does); the reporting DB uses
   a different, case-insensitive one, to prove there are no collation conflicts.
   Each row is commented with the behaviour it tests.
   ============================================================================= */

:on error exit
SET NOCOUNT ON;
GO
/* SAFETY GUARD. This script DROPS databases named like production.
   It only drops a database that carries the marker table dbo.__mock_marker,
   i.e. one this script created. On a real server it stops here, and
   SET NOEXEC ON stops every later batch even outside sqlcmd. */
IF (DB_ID(N'BTL_LS_LIVE') IS NOT NULL AND OBJECT_ID(N'BTL_LS_LIVE.dbo.__mock_marker') IS NULL)
OR (DB_ID(N'FAKHRA_LIVE') IS NOT NULL AND OBJECT_ID(N'FAKHRA_LIVE.dbo.__mock_marker') IS NULL)
OR (DB_ID(N'BATEEL_RPT')  IS NOT NULL AND OBJECT_ID(N'BATEEL_RPT.dbo.__mock_marker')  IS NULL)
BEGIN
    RAISERROR (N'Refusing to run: a database with a production name exists and was not created by this test. Use a disposable server.', 16, 1);
    SET NOEXEC ON;
END;
GO
IF DB_ID(N'BATEEL_RPT')  IS NOT NULL BEGIN ALTER DATABASE BATEEL_RPT  SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE BATEEL_RPT;  END;
IF DB_ID(N'BTL_LS_LIVE') IS NOT NULL BEGIN ALTER DATABASE BTL_LS_LIVE SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE BTL_LS_LIVE; END;
IF DB_ID(N'FAKHRA_LIVE') IS NOT NULL BEGIN ALTER DATABASE FAKHRA_LIVE SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE FAKHRA_LIVE; END;
GO
CREATE DATABASE BTL_LS_LIVE COLLATE Latin1_General_100_CS_AS;
CREATE DATABASE FAKHRA_LIVE COLLATE Latin1_General_100_CS_AS;
CREATE DATABASE BATEEL_RPT  COLLATE SQL_Latin1_General_CP1_CI_AS;
GO
EXEC (N'CREATE TABLE BTL_LS_LIVE.dbo.__mock_marker (Id INT)');
EXEC (N'CREATE TABLE FAKHRA_LIVE.dbo.__mock_marker (Id INT)');
EXEC (N'CREATE TABLE BATEEL_RPT.dbo.__mock_marker (Id INT)');
GO

USE BTL_LS_LIVE;
GO
CREATE TABLE dbo.[Jedoxdept] (Navision_ID NVARCHAR(20), Division_ID NVARCHAR(50), Division_Desc NVARCHAR(100), Department_Desc NVARCHAR(100));
INSERT INTO dbo.[Jedoxdept] VALUES
    (N'1001', N'RETAIL',    N'Retail',    N'Dubai Mall'),
    (N'1300', N'Franchise', N'Franchise', N'Franchise Partners'),   -- mixed case: old CS filter missed it
    (N'1196', N'RETAIL',    N'Retail',    N'Retail Ecom UAE'),      -- DEPT rule must move it to ECOM
    (N'3001', N'RETAIL',    N'Retail',    N'Riyadh Store'),
    (N'3193', N'CORPORATE', N'Corporate', N'Corporate KSA');
GO

DECLARE @co NVARCHAR(20);
DECLARE @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT v FROM (VALUES (N'BATEEL-UAE'), (N'BATEEL-KSA')) t (v);
OPEN c; FETCH NEXT FROM c INTO @co;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    CREATE TABLE dbo.[' + @co + N'$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ( [Entry No_] INT IDENTITY, [Posting Date] DATETIME, [Item Ledger Entry Type] INT, [Item No_] NVARCHAR(20),
      [Location Code] NVARCHAR(10), [Source Type] INT, [Source No_] NVARCHAR(20),
      [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20),
      [Sales Amount (Actual)] DECIMAL(38,20), [Item Ledger Entry Quantity] DECIMAL(38,20) );
    CREATE TABLE dbo.[' + @co + N'$Item$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ( [No_] NVARCHAR(20), [Description] NVARCHAR(100), [Item Category Code] NVARCHAR(20), [Base Unit of Measure] NVARCHAR(10) );
    CREATE TABLE dbo.[' + @co + N'$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ( [Entry No_] INT IDENTITY, [Posting Date] DATETIME, [G_L Account No_] NVARCHAR(20), [Amount] DECIMAL(38,20),
      [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20) );
    CREATE TABLE dbo.[' + @co + N'$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ( [Entry No_] INT IDENTITY, [Budget Name] NVARCHAR(10), [Date] DATETIME, [G_L Account No_] NVARCHAR(20), [Amount] DECIMAL(38,20),
      [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20) );';
    EXEC (@sql);
    FETCH NEXT FROM c INTO @co;
END;
CLOSE c; DEALLOCATE c;
GO

INSERT INTO dbo.[BATEEL-UAE$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES
    (N'ITM1', N'Khidri Dates 500g', N'DATES', N'PCS'),
    (N'ITM2', N'Praline Box 16pc',  N'CHOCOLATE', N'PCS');

-- BC signs: sale = positive Sales Amount, negative quantity.
INSERT INTO dbo.[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [Item Ledger Entry Type], [Item No_], [Location Code], [Source Type], [Source No_],
     [Global Dimension 1 Code], [Global Dimension 2 Code], [Sales Amount (Actual)], [Item Ledger Entry Quantity])
VALUES
    ('2026-09-10', 1, N'ITM1', N'DXB1', 0, N'',     N'',     N'1001', 1000, -10),  -- RETAIL
    ('2026-09-11', 1, N'ITM1', N'DXB1', 1, N'C001', N'1010', N'1001', 500,  -5),   -- AIRLINES by cust cat, dept is RETAIL: count once
    ('2026-09-12', 1, N'ITM2', N'FRN1', 1, N'F001', N'',     N'1300', 200,  -2),   -- FRANCHISE via mixed-case Jedoxdept
    ('2026-09-13', 1, N'ITM2', N'WEB',  0, N'',     N'',     N'1196', 300,  -3),   -- ECOM via DEPT rule
    ('2026-09-14', 1, N'ITM2', N'XXX',  0, N'',     N'',     N'9999', 50,   -1),   -- UNASSIGNED, must not be dropped
    ('2026-09-15', 0, N'ITM1', N'DXB1', 2, N'V001', N'',     N'1001', 0,    100),  -- purchase: excluded
    ('2024-01-15', 1, N'ITM1', N'DXB1', 0, N'',     N'',     N'1001', 999,  -9);   -- outside 24-month window

INSERT INTO dbo.[BATEEL-UAE$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES
    ('2026-09-10', N'30100', -1500, N'',     N'1001'),   -- RETAIL net sales 1500
    ('2026-09-11', N'30100', -500,  N'1010', N'1001'),   -- AIRLINES 500, not also RETAIL
    ('2026-09-12', N'30160', -80,   N'',     N'1001'),   -- Other Income, never Net Sales
    ('2026-09-12', N'41100', 700,   N'',     N'1001'),   -- COGS: out of scope
    ('2025-12-15', N'30100', -1500, N'',     N'1001'),   -- December sales
    ('2025-12-31 23:59:59', N'30100', 1500, N'', N'1001'); -- year-end closing entry: excluded

INSERT INTO dbo.[BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Budget Name], [Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES
    (N'2026FSBUDJ', '2026-09-01', N'30100', -2000, N'',     N'1001'),  -- RETAIL budget 2000
    (N'2026FSBUDJ', '2026-09-01', N'30100', -600,  N'1010', N'1001'),  -- AIRLINES budget 600, dept key stays 1001
    (N'2026FSBUDJ', '2026-09-01', N'30160', -50,   N'',     N'1001'),  -- Other Income budget
    (N'2026FSBUDJ', '2026-12-01', N'30100', -2400, N'',     N'1001'),  -- future month: must load (no cut-off at today)
    (N'OLDBUD',     '2026-09-01', N'30100', -999,  N'',     N'1001');  -- inactive budget name: excluded

INSERT INTO dbo.[BATEEL-KSA$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES (N'ITM1', N'Khidri Dates 500g', N'DATES', N'PCS');

INSERT INTO dbo.[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [Item Ledger Entry Type], [Item No_], [Location Code], [Source Type], [Source No_],
     [Global Dimension 1 Code], [Global Dimension 2 Code], [Sales Amount (Actual)], [Item Ledger Entry Quantity])
VALUES
    ('2026-09-10', 1, N'ITM1', N'RUH1', 0, N'',     N'', N'3001', 1000, -10),   -- RETAIL, SAR 1000 = AED 979.333
    ('2026-09-10', 1, N'ITM1', N'RUH1', 1, N'K001', N'', N'3193', 100,  -1);    -- B2B via DEPT rule

INSERT INTO dbo.[BATEEL-KSA$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES ('2026-09-10', N'30100', -1000, N'', N'3001');

INSERT INTO dbo.[BATEEL-KSA$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Budget Name], [Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES (N'2026FSBUDJ', '2026-09-01', N'30100', -1000, N'', N'3001');
GO

USE FAKHRA_LIVE;
GO
CREATE TABLE dbo.[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [Entry No_] INT IDENTITY, [Posting Date] DATETIME, [Item Ledger Entry Type] INT, [Item No_] NVARCHAR(20),
  [Location Code] NVARCHAR(10), [Source Type] INT, [Source No_] NVARCHAR(20),
  [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20),
  [Sales Amount (Actual)] DECIMAL(38,20), [Item Ledger Entry Quantity] DECIMAL(38,20) );
CREATE TABLE dbo.[Al Fakhra Date$Item$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [No_] NVARCHAR(20), [Description] NVARCHAR(100), [Item Category Code] NVARCHAR(20), [Base Unit of Measure] NVARCHAR(10) );
CREATE TABLE dbo.[Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [Entry No_] INT IDENTITY, [Posting Date] DATETIME, [G_L Account No_] NVARCHAR(20), [Amount] DECIMAL(38,20),
  [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20) );
CREATE TABLE dbo.[Al Fakhra Date$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [Entry No_] INT IDENTITY, [Budget Name] NVARCHAR(10), [Date] DATETIME, [G_L Account No_] NVARCHAR(20), [Amount] DECIMAL(38,20),
  [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20) );
CREATE TABLE dbo.[Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [Dimension Code] NVARCHAR(20), [Code] NVARCHAR(20), [Name] NVARCHAR(100) );
CREATE TABLE dbo.[Al Fakhra Date$General Ledger Setup$437dbf0e-84ff-417a-965d-ed2bb9650972]
( [Primary Key] NVARCHAR(10), [Global Dimension 1 Code] NVARCHAR(20), [Global Dimension 2 Code] NVARCHAR(20) );
GO

INSERT INTO dbo.[Al Fakhra Date$General Ledger Setup$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES (N'', N'DEPARTMENT', N'PROJECT');
INSERT INTO dbo.[Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES
    (N'DEPARTMENT', N'014', N'Jomara Distribution KSA'),
    (N'AAPROJECT',  N'014', N'Wrong dimension'),          -- old TOP 1 ORDER BY Dimension Code picked this
    (N'DEPARTMENT', N'011', N'Farms');
INSERT INTO dbo.[Al Fakhra Date$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] VALUES (N'DT01', N'Sukkari Bulk', N'DATES', N'KG');

INSERT INTO dbo.[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [Item Ledger Entry Type], [Item No_], [Location Code], [Source Type], [Source No_],
     [Global Dimension 1 Code], [Global Dimension 2 Code], [Sales Amount (Actual)], [Item Ledger Entry Quantity])
VALUES
    ('2026-09-10', 1, N'DT01', N'FRM1', 1, N'J001', N'014',  N'', 1000, -100),  -- JOMARA Distributor KSA
    ('2026-09-10', 1, N'DT01', N'FRM1', 1, N'B001', N'011',  N'', 500,  -50),   -- BULK
    ('2026-09-10', 1, N'DT01', N'FRM1', 1, N'X001', N'019',  N'', 70,   -7),    -- unmapped: UNASSIGNED, not dropped
    ('2026-09-10', 1, N'DT01', N'FRM1', 1, N'P001', N' 017', N'', 30,   -3);    -- padded code: trimmed -> Private Label

INSERT INTO dbo.[Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Posting Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES ('2026-09-10', N'30100', -1000, N'014', N'');

INSERT INTO dbo.[Al Fakhra Date$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972]
    ([Budget Name], [Date], [G_L Account No_], [Amount], [Global Dimension 1 Code], [Global Dimension 2 Code])
VALUES (N'2026 BUD', '2026-09-01', N'30100', -900, N'014', N'');   -- name differs from cfg: coverage must show 0
GO
