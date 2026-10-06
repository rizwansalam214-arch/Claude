/* =============================================================================
   01 — Source synonyms
   The only place BC table names (with the extension GUID) appear. If a
   database is renamed or moved, change it here and nothing else.
   ============================================================================= */

DROP SYNONYM IF EXISTS src.UAE_ValueEntry;
DROP SYNONYM IF EXISTS src.UAE_Item;
DROP SYNONYM IF EXISTS src.UAE_GLEntry;
DROP SYNONYM IF EXISTS src.UAE_GLBudgetEntry;
DROP SYNONYM IF EXISTS src.KSA_ValueEntry;
DROP SYNONYM IF EXISTS src.KSA_Item;
DROP SYNONYM IF EXISTS src.KSA_GLEntry;
DROP SYNONYM IF EXISTS src.KSA_GLBudgetEntry;
DROP SYNONYM IF EXISTS src.FAKHRA_ValueEntry;
DROP SYNONYM IF EXISTS src.FAKHRA_Item;
DROP SYNONYM IF EXISTS src.FAKHRA_GLEntry;
DROP SYNONYM IF EXISTS src.FAKHRA_GLBudgetEntry;
DROP SYNONYM IF EXISTS src.FAKHRA_DimensionValue;
DROP SYNONYM IF EXISTS src.FAKHRA_GLSetup;
DROP SYNONYM IF EXISTS src.Jedoxdept;
GO

-- BATEEL-UAE (BTL_LS_LIVE)
CREATE SYNONYM src.UAE_ValueEntry       FOR [BTL_LS_LIVE].[dbo].[BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.UAE_Item             FOR [BTL_LS_LIVE].[dbo].[BATEEL-UAE$Item$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.UAE_GLEntry          FOR [BTL_LS_LIVE].[dbo].[BATEEL-UAE$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.UAE_GLBudgetEntry    FOR [BTL_LS_LIVE].[dbo].[BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];

-- BATEEL-KSA (BTL_LS_LIVE)
CREATE SYNONYM src.KSA_ValueEntry       FOR [BTL_LS_LIVE].[dbo].[BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.KSA_Item             FOR [BTL_LS_LIVE].[dbo].[BATEEL-KSA$Item$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.KSA_GLEntry          FOR [BTL_LS_LIVE].[dbo].[BATEEL-KSA$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.KSA_GLBudgetEntry    FOR [BTL_LS_LIVE].[dbo].[BATEEL-KSA$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];

-- Al Fakhra (FAKHRA_LIVE)
CREATE SYNONYM src.FAKHRA_ValueEntry    FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.FAKHRA_Item          FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$Item$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.FAKHRA_GLEntry       FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.FAKHRA_GLBudgetEntry FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.FAKHRA_DimensionValue FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972];
CREATE SYNONYM src.FAKHRA_GLSetup       FOR [FAKHRA_LIVE].[dbo].[Al Fakhra Date$General Ledger Setup$437dbf0e-84ff-417a-965d-ed2bb9650972];

-- Department -> division master (shared by UAE and KSA)
CREATE SYNONYM src.Jedoxdept            FOR [BTL_LS_LIVE].[dbo].[Jedoxdept];
GO
