/* =============================================================================
   02 — Configuration tables (DDL)
   Everything Finance may need to change lives here as data, not code.
   ============================================================================= */

IF OBJECT_ID(N'cfg.Setting') IS NULL
CREATE TABLE cfg.Setting
(
    SettingKey   NVARCHAR(50)  NOT NULL CONSTRAINT PK_cfg_Setting PRIMARY KEY,
    SettingValue NVARCHAR(200) NOT NULL,
    Note         NVARCHAR(400) NULL
);

IF OBJECT_ID(N'cfg.FxRate') IS NULL
CREATE TABLE cfg.FxRate
(
    CurrencyCode NVARCHAR(3)    NOT NULL CONSTRAINT PK_cfg_FxRate PRIMARY KEY,
    RateToAED    DECIMAL(18, 8) NOT NULL CONSTRAINT CK_cfg_FxRate_Positive CHECK (RateToAED > 0),
    Note         NVARCHAR(400)  NULL
);

IF OBJECT_ID(N'cfg.Company') IS NULL
CREATE TABLE cfg.Company
(
    Company        NVARCHAR(10) NOT NULL CONSTRAINT PK_cfg_Company PRIMARY KEY,
    CompanyName    NVARCHAR(50) NOT NULL,
    CurrencyCode   NVARCHAR(3)  NOT NULL CONSTRAINT FK_cfg_Company_Fx REFERENCES cfg.FxRate (CurrencyCode),
    SourceDatabase NVARCHAR(50) NOT NULL
);

IF OBJECT_ID(N'cfg.Segment') IS NULL
CREATE TABLE cfg.Segment
(
    SegmentCode  NVARCHAR(20)  NOT NULL CONSTRAINT PK_cfg_Segment PRIMARY KEY,
    SegmentLabel NVARCHAR(100) NOT NULL,
    SortOrder    INT           NOT NULL
);

/* One row per mapping rule.
   Precedence (lowest Priority wins): CUSTCAT 10 > DEPT 20 > DIVISION 30.
   This is the "customer category takes precedence" rule from §3, extended so
   an explicit department rule (e.g. 1196 -> ECOM, 3193 -> B2B) beats the
   Jedoxdept division of that department. A transaction resolves to exactly
   one rule, so it is counted once. */
IF OBJECT_ID(N'cfg.SegmentRule') IS NULL
CREATE TABLE cfg.SegmentRule
(
    RuleId      INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_cfg_SegmentRule PRIMARY KEY,
    Company     NVARCHAR(10)  NOT NULL CONSTRAINT FK_cfg_SegmentRule_Company REFERENCES cfg.Company (Company),
    RuleType    NVARCHAR(10)  NOT NULL CONSTRAINT CK_cfg_SegmentRule_Type CHECK (RuleType IN (N'CUSTCAT', N'DEPT', N'DIVISION')),
    MatchCode   NVARCHAR(50)  NOT NULL,
    SegmentCode NVARCHAR(20)  NOT NULL CONSTRAINT FK_cfg_SegmentRule_Segment REFERENCES cfg.Segment (SegmentCode),
    SubLine     NVARCHAR(100) NULL,
    SubLineSort INT           NULL,
    Status      NVARCHAR(12)  NOT NULL CONSTRAINT CK_cfg_SegmentRule_Status CHECK (Status IN (N'AGREED', N'PROVISIONAL')),
    Note        NVARCHAR(400) NULL,
    IsActive    BIT           NOT NULL CONSTRAINT DF_cfg_SegmentRule_IsActive DEFAULT (1),
    Priority AS CAST(CASE RuleType WHEN N'CUSTCAT' THEN 10 WHEN N'DEPT' THEN 20 ELSE 30 END AS INT) PERSISTED
);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_cfg_SegmentRule_Match')
CREATE UNIQUE INDEX UX_cfg_SegmentRule_Match
    ON cfg.SegmentRule (Company, RuleType, MatchCode)
    WHERE IsActive = 1;

/* G/L accounts inside 3* that are Other Income, never Net Sales. */
IF OBJECT_ID(N'cfg.OtherIncomeAccount') IS NULL
CREATE TABLE cfg.OtherIncomeAccount
(
    GLAccountNo NVARCHAR(20)  NOT NULL CONSTRAINT PK_cfg_OtherIncomeAccount PRIMARY KEY,
    Note        NVARCHAR(400) NULL
);

/* Which BC budget name is the budget for each company and fiscal year. */
IF OBJECT_ID(N'cfg.BudgetVersion') IS NULL
CREATE TABLE cfg.BudgetVersion
(
    Company    NVARCHAR(10) NOT NULL CONSTRAINT FK_cfg_BudgetVersion_Company REFERENCES cfg.Company (Company),
    FiscalYear INT          NOT NULL,
    BudgetName NVARCHAR(50) NOT NULL,
    Status     NVARCHAR(12) NOT NULL CONSTRAINT CK_cfg_BudgetVersion_Status CHECK (Status IN (N'AGREED', N'PROVISIONAL')),
    IsActive   BIT          NOT NULL CONSTRAINT DF_cfg_BudgetVersion_IsActive DEFAULT (1),
    CONSTRAINT PK_cfg_BudgetVersion PRIMARY KEY (Company, FiscalYear)
);
GO
