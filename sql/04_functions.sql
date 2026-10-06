/* =============================================================================
   04 — Resolution functions (inline, so the optimiser expands them)
   ============================================================================= */

/* Department code -> Jedoxdept division.
   Exact (trimmed) string match first; numeric match only as a fallback, so a
   non-numeric code no longer silently drops out (old TRY_CONVERT-only join).
   Division_ID is UPPER/TRIMmed: the BC databases use a case-sensitive
   collation, so 'Franchise' <> 'FRANCHISE' in the old extracts. */
CREATE OR ALTER FUNCTION rpt.fnDivision (@DeptCode NVARCHAR(30))
RETURNS TABLE
AS
RETURN
    SELECT TOP (1)
        UPPER(LTRIM(RTRIM(CAST(JD.[Division_ID] AS NVARCHAR(50))))) COLLATE DATABASE_DEFAULT AS DivisionId,
        CAST(JD.[Division_Desc]   AS NVARCHAR(100)) COLLATE DATABASE_DEFAULT AS DivisionDesc,
        CAST(JD.[Department_Desc] AS NVARCHAR(100)) COLLATE DATABASE_DEFAULT AS DepartmentDesc
    FROM src.Jedoxdept JD
    WHERE @DeptCode IS NOT NULL
      AND @DeptCode <> N''
      AND
      (
          LTRIM(RTRIM(CAST(JD.[Navision_ID] AS NVARCHAR(30)))) COLLATE DATABASE_DEFAULT = @DeptCode
          OR
          (
              TRY_CONVERT(INT, @DeptCode) IS NOT NULL
              AND TRY_CONVERT(INT, JD.[Navision_ID]) = TRY_CONVERT(INT, @DeptCode)
          )
      )
    ORDER BY
        CASE WHEN LTRIM(RTRIM(CAST(JD.[Navision_ID] AS NVARCHAR(30)))) COLLATE DATABASE_DEFAULT = @DeptCode THEN 0 ELSE 1 END;
GO

/* (company, customer category, department, division) -> one segment.
   Lowest Priority wins (CUSTCAT > DEPT > DIVISION). IsOverride = 1 when a
   lower-priority rule would have put the same row in a different segment:
   these are exactly the rows the old extracts counted twice. */
CREATE OR ALTER FUNCTION rpt.fnResolveSegment
(
    @Company     NVARCHAR(10),
    @CustCatCode NVARCHAR(30),
    @DeptCode    NVARCHAR(30),
    @DivisionId  NVARCHAR(50)
)
RETURNS TABLE
AS
RETURN
    WITH M AS
    (
        SELECT R.RuleId, R.RuleType, R.Priority, R.SegmentCode, R.SubLine, R.SubLineSort, R.Status
        FROM cfg.SegmentRule R
        WHERE R.IsActive = 1
          AND R.Company = @Company
          AND
          (
                 (R.RuleType = N'CUSTCAT'  AND R.MatchCode = @CustCatCode)
              OR (R.RuleType = N'DEPT'     AND R.MatchCode = @DeptCode)
              OR (R.RuleType = N'DIVISION' AND R.MatchCode = @DivisionId)
          )
    )
    SELECT TOP (1)
        M.RuleId,
        M.RuleType,
        M.SegmentCode,
        M.SubLine,
        M.SubLineSort,
        M.Status AS RuleStatus,
        CAST(CASE WHEN (SELECT COUNT(DISTINCT M2.SegmentCode) FROM M M2) > 1 THEN 1 ELSE 0 END AS BIT) AS IsOverride
    FROM M
    ORDER BY M.Priority;
GO
