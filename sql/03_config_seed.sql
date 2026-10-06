/* =============================================================================
   03 — Configuration seed (from build prompt v2, Appendix A and B)
   Re-runnable: replaces the seeded rows each time. PROVISIONAL rows are the
   open items; their amounts are surfaced on rpt.dqProvisionalMappings.
   ============================================================================= */

SET NOCOUNT ON;

DELETE FROM cfg.SegmentRule;
DELETE FROM cfg.BudgetVersion;
DELETE FROM cfg.Company;
DELETE FROM cfg.Segment;
DELETE FROM cfg.FxRate;
DELETE FROM cfg.OtherIncomeAccount;
DELETE FROM cfg.Setting;

INSERT INTO cfg.Setting (SettingKey, SettingValue, Note) VALUES
    (N'HISTORY_MONTHS', N'24', N'Full months of history loaded before the current month (LY / LFL need >= 12).');

INSERT INTO cfg.FxRate (CurrencyCode, RateToAED, Note) VALUES
    (N'AED', 1.00000000, N'Report currency'),
    (N'SAR', 0.97933300, N'Single group rate (3.6725 / 3.75)');

INSERT INTO cfg.Company (Company, CompanyName, CurrencyCode, SourceDatabase) VALUES
    (N'UAE',    N'BATEEL-UAE', N'AED', N'BTL_LS_LIVE'),
    (N'KSA',    N'BATEEL-KSA', N'SAR', N'BTL_LS_LIVE'),
    (N'FAKHRA', N'Al Fakhra',  N'SAR', N'FAKHRA_LIVE');

INSERT INTO cfg.Segment (SegmentCode, SegmentLabel, SortOrder) VALUES
    (N'RETAIL',     N'Retail',                     1),
    (N'CAFE',       N'Café & El''an',              2),
    (N'B2B',        N'B2B & Hotels',               3),
    (N'TRAVEL',     N'Travel Retail / Duty Free',  4),
    (N'JOMARA',     N'Jomara',                     5),
    (N'FRANCHISE',  N'Franchise (incl. SNS)',      6),
    (N'ECOM',       N'E-commerce',                 7),
    (N'AIRLINES',   N'Airlines',                   8),
    (N'BULK',       N'Bulk Sales (Farms)',         9),
    (N'UNASSIGNED', N'Unassigned',                99);

INSERT INTO cfg.OtherIncomeAccount (GLAccountNo, Note) VALUES
    (N'30160', N'Other Income'),
    (N'30161', N'Other Income'),
    (N'30162', N'Other Income'),
    (N'30163', N'Other Income'),
    (N'30170', N'Other Income');

INSERT INTO cfg.BudgetVersion (Company, FiscalYear, BudgetName, Status) VALUES
    (N'UAE',    2026, N'2026FSBUDJ', N'AGREED'),
    (N'KSA',    2026, N'2026FSBUDJ', N'AGREED'),
    (N'FAKHRA', 2026, N'2026BUD',    N'PROVISIONAL');   -- name unverified: diagnostics/04_fakhra_checks.sql

INSERT INTO cfg.SegmentRule (Company, RuleType, MatchCode, SegmentCode, SubLine, SubLineSort, Status, Note) VALUES
    /* ---- UAE customer categories (Global Dimension 1) ---- */
    (N'UAE', N'CUSTCAT', N'1080', N'B2B',      N'Hotels',                     NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1020', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1030', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1040', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1060', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1070', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1090', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1100', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1131', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1190', N'B2B',      N'Corporates & Institutions',  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1010', N'AIRLINES', N'Airlines',                   NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1160', N'TRAVEL',   N'Duty Free',                  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1182', N'TRAVEL',   N'Duty Free',                  NULL, N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1150', N'JOMARA',   N'Jomara Supermarket — UAE',   1,    N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1151', N'JOMARA',   N'Jomara Distributor — UAE',   2,    N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1152', N'JOMARA',   N'Jomara Dark Stores — UAE',   3,    N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1180', N'JOMARA',   N'UAE Exports',                7,    N'AGREED', NULL),
    (N'UAE', N'CUSTCAT', N'1181', N'JOMARA',   N'UAE Exports',                7,    N'PROVISIONAL', N'Open decision #1'),

    /* ---- Explicit department rules (beat the Jedoxdept division) ---- */
    (N'UAE', N'DEPT', N'1196', N'ECOM', NULL, NULL, N'AGREED', N'Retail Ecom UAE'),
    (N'UAE', N'DEPT', N'1120', N'ECOM', NULL, NULL, N'AGREED', NULL),
    (N'UAE', N'DEPT', N'1601', N'ECOM', NULL, NULL, N'AGREED', NULL),
    (N'UAE', N'DEPT', N'1602', N'ECOM', NULL, NULL, N'AGREED', NULL),
    (N'UAE', N'DEPT', N'1603', N'ECOM', NULL, NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3188', N'ECOM', NULL, NULL, N'AGREED', N'Retail Ecom KSA'),
    (N'KSA', N'DEPT', N'3193', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3194', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3195', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3308', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3309', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),
    (N'KSA', N'DEPT', N'3310', N'B2B',  N'Corporate / Hotels KSA', NULL, N'AGREED', NULL),

    /* ---- Al Fakhra departments (Global Dimension 1) ---- */
    (N'FAKHRA', N'DEPT', N'014',   N'JOMARA', N'Jomara Distributor — KSA',  4,  N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'015',   N'JOMARA', N'Jomara Local Sales — KSA',  5,  N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'018',   N'JOMARA', N'Jomara Dark Stores — KSA',  6,  N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'016',   N'JOMARA', N'KSA Exports',               8,  N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'011-1', N'JOMARA', N'Bulk / Wholesales',         9,  N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'017',   N'JOMARA', N'KSA Private Label',         10, N'PROVISIONAL', N'Code unverified'),
    (N'FAKHRA', N'DEPT', N'011',   N'BULK',   N'Farms',                     NULL, N'AGREED', NULL),
    (N'FAKHRA', N'DEPT', N'013-1', N'BULK',   N'Farms',                     NULL, N'AGREED', NULL);

/* ---- Jedoxdept Division_ID -> segment (UAE and KSA share Jedoxdept).
        Matched after UPPER/TRIM, so 'Franchise' and 'FRANCHISE' both hit. ---- */
INSERT INTO cfg.SegmentRule (Company, RuleType, MatchCode, SegmentCode, SubLine, SubLineSort, Status, Note)
SELECT C.Company, N'DIVISION', D.DivisionId, D.SegmentCode, D.SubLine, NULL, D.Status, D.Note
FROM (VALUES (N'UAE'), (N'KSA')) C (Company)
CROSS JOIN
(
    VALUES
        (N'RETAIL',     N'RETAIL',    N'Retail',    N'AGREED',      NULL),
        (N'CAFE',       N'CAFE',      N'Café',      N'AGREED',      NULL),
        (N'ELAN',       N'CAFE',      N'El''an',    N'AGREED',      NULL),
        (N'E-COMMERCE', N'ECOM',      NULL,         N'AGREED',      NULL),
        (N'ECOM',       N'ECOM',      NULL,         N'AGREED',      NULL),
        (N'ECOMMERCE',  N'ECOM',      NULL,         N'AGREED',      NULL),
        (N'FRANCHISE',  N'FRANCHISE', N'Franchise', N'AGREED',      NULL),
        (N'FRANCHAISE', N'FRANCHISE', N'Franchise', N'AGREED',      N'Misspelt variant seen in extracts'),
        (N'SNS',        N'FRANCHISE', N'SNS',       N'PROVISIONAL', N'Division_ID string unverified')
) D (DivisionId, SegmentCode, SubLine, Status, Note);
GO
