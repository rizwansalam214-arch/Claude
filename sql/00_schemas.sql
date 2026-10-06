/* =============================================================================
   00 — Schemas
   Run in the REPORTING database (e.g. BATEEL_RPT), never in BTL_LS_LIVE or
   FAKHRA_LIVE. The BC databases stay read-only; everything below lives here.

   cfg  maintained configuration (mappings, FX, budget versions)
   src  synonyms pointing at the BC source tables
   rpt  semantic layer: functions, source views, fact tables, DQ views
   ============================================================================= */

IF SCHEMA_ID(N'cfg') IS NULL EXEC (N'CREATE SCHEMA cfg');
IF SCHEMA_ID(N'src') IS NULL EXEC (N'CREATE SCHEMA src');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt');
GO
