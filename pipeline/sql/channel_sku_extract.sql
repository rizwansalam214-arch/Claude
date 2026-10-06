/* =============================================================================
   CHANNEL & SKU EXTRACT — pipeline copy (patched)
   Source: channel_sku_extract.original.sql. Changes are marked "-- FIX n":
     FIX 1  Extract starts 1 Jan of LAST year (vs LY comparisons).
     FIX 2  Budget runs to 31 Dec of this year, not cut at today.
     FIX 3  Division_ID filters are case/space-insensitive (case-sensitive BC collation).
     FIX 4  UAE division blocks (actual + budget) exclude rows whose customer
            category is reported in the customer-category block: counted once.
     FIX 5  Other Income accounts 30160-30163, 30170 excluded from Sales Budget.
     FIX 6  Year-end closing entries excluded from Other Income.
   NOT changed here (handled in build_dashboard.py, configurable):
     - Sign: Sales = SUM(-Sales Amount) and Quantity come out negative under
       BC's standard convention; the pipeline flips them and aborts if the
       result is not positive (see config "sign").
     - SAR -> AED conversion.
     - COGS columns are extracted but not shown (COGS rule not agreed).
   ============================================================================= */

USE [BTL_LS_LIVE];
GO

DECLARE @FromDate   DATE         = DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1);   -- FIX 1: from 1 Jan LAST year (needed for vs LY)
DECLARE @BudgetToDate DATE       = DATEFROMPARTS(YEAR(GETDATE()), 12, 31);     -- FIX 2: full-year budget, not cut at today
DECLARE @ToDate     DATE         = CAST(GETDATE() AS DATE);
DECLARE @BudgetName NVARCHAR(50) = N'2026FSBUDJ';
DECLARE @FakhraBudgetName NVARCHAR(50) = N'2026BUD';
DECLARE @DeptDim    NVARCHAR(50) = N'DEPARTMENT';
DECLARE @CustCatDim NVARCHAR(50) = N'CUSTOMER CATEGORY';

;WITH ActualRaw AS
(
    /* ============================================================
       UAE - CUSTOMER CATEGORY SALES
       ============================================================ */
    SELECT
        N'UAE' AS [Company],
        N'CUSTOMER CATEGORY' AS [Source Type],
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120) AS [YearMonth],

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT AS [Division],

        ISNULL(VE.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT AS [Department Code],

        ISNULL(DVD.[Name], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Department],

        ISNULL(VE.[Global Dimension 1 Code], '')
            COLLATE DATABASE_DEFAULT AS [Customer Category Code],

        ISNULL(DVC.[Name], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Customer Category],

        I.[No_] COLLATE DATABASE_DEFAULT AS [SKU],
        I.[Description] COLLATE DATABASE_DEFAULT AS [Item Description],

        I.[Base Unit of Measure]
            COLLATE DATABASE_DEFAULT AS [Base Unit of Measure],

        SUM(-VE.[Sales Amount (Actual)]) AS [Sales],
        SUM(VE.[Cost Amount (Actual)]) AS [COGS],

        SUM(
            -VE.[Sales Amount (Actual)]
            - VE.[Cost Amount (Actual)]
        ) AS [GM],

        SUM(VE.[Item Ledger Entry Quantity]) AS [Quantity]

    FROM
        [BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(VE.[Posting Date]),
                MONTH(VE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        [BATEEL-UAE$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] I
        WITH (NOLOCK)
        ON I.[No_] = VE.[Item No_]

    LEFT JOIN
        [BATEEL-UAE$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DVD
        WITH (NOLOCK)
        ON DVD.[Code] = VE.[Global Dimension 2 Code]
       AND DVD.[Dimension Code] = @DeptDim

    LEFT JOIN
        [BATEEL-UAE$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DVC
        WITH (NOLOCK)
        ON DVC.[Code] = VE.[Global Dimension 1 Code]
       AND DVC.[Dimension Code] = @CustCatDim

    WHERE
        VE.[Item Ledger Entry Type] = 1
        AND VE.[Posting Date] >= @FromDate
        AND VE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND VE.[Global Dimension 1 Code] IN
        (
            '1010','1080','1150','1151','1152',
            '1160','1182','1180','1181',
            '1040','1020','1030','1060','1070',
            '1090','1100','1190','1131'
        )

    GROUP BY
        M.[Month Start],
        ISNULL(VE.[Global Dimension 2 Code], ''),
        ISNULL(DVD.[Name], 'Unmapped'),
        ISNULL(VE.[Global Dimension 1 Code], ''),
        ISNULL(DVC.[Name], 'Unmapped'),
        I.[No_],
        I.[Description],
        I.[Base Unit of Measure]

    UNION ALL

    /* ============================================================
       UAE - DIVISION SALES
       ============================================================ */
    SELECT
        N'UAE',
        N'DIVISION',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        ISNULL(VE.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT,

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        I.[No_] COLLATE DATABASE_DEFAULT,
        I.[Description] COLLATE DATABASE_DEFAULT,

        I.[Base Unit of Measure]
            COLLATE DATABASE_DEFAULT,

        SUM(-VE.[Sales Amount (Actual)]),
        SUM(VE.[Cost Amount (Actual)]),

        SUM(
            -VE.[Sales Amount (Actual)]
            - VE.[Cost Amount (Actual)]
        ),

        SUM(VE.[Item Ledger Entry Quantity])

    FROM
        [BATEEL-UAE$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(VE.[Posting Date]),
                MONTH(VE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        [BATEEL-UAE$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] I
        WITH (NOLOCK)
        ON I.[No_] = VE.[Item No_]

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, VE.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        VE.[Item Ledger Entry Type] = 1
        AND VE.[Posting Date] >= @FromDate
        AND VE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND UPPER(LTRIM(RTRIM(JD.[Division_ID]))) IN   -- FIX 3: case/space-insensitive
        (
            'CAFE',
            'E-COMMERCE',
            'ECOM',
            'ECOMMERCE',
            'ELAN',
            'FRANCHISE',
            'FRANCHAISE',
            'RETAIL',
            'SNS'
        )

        -- FIX 4: these rows are already reported by customer category; exclude so they are counted once
        AND LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) NOT IN ('1010','1080','1150','1151','1152','1160','1182','1180','1181','1040','1020','1030','1060','1070','1090','1100','1190','1131')

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(VE.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped'),
        I.[No_],
        I.[Description],
        I.[Base Unit of Measure]

    UNION ALL

    /* ============================================================
       KSA - DIVISION SALES
       ============================================================ */
    SELECT
        N'KSA',
        N'DIVISION',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        ISNULL(VE.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT,

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        I.[No_] COLLATE DATABASE_DEFAULT,
        I.[Description] COLLATE DATABASE_DEFAULT,

        I.[Base Unit of Measure]
            COLLATE DATABASE_DEFAULT,

        SUM(-VE.[Sales Amount (Actual)]),
        SUM(VE.[Cost Amount (Actual)]),

        SUM(
            -VE.[Sales Amount (Actual)]
            - VE.[Cost Amount (Actual)]
        ),

        SUM(VE.[Item Ledger Entry Quantity])

    FROM
        [BATEEL-KSA$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(VE.[Posting Date]),
                MONTH(VE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        [BATEEL-KSA$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] I
        WITH (NOLOCK)
        ON I.[No_] = VE.[Item No_]

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, VE.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        VE.[Item Ledger Entry Type] = 1
        AND VE.[Posting Date] >= @FromDate
        AND VE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(VE.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped'),
        I.[No_],
        I.[Description],
        I.[Base Unit of Measure]

    UNION ALL

    /* ============================================================
       FAKHRA - SALES
       ============================================================ */
    SELECT
        N'FAKHRA',
        N'DIVISION',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        CASE
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END COLLATE DATABASE_DEFAULT,

        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], '')))
            COLLATE DATABASE_DEFAULT,

        ISNULL(DV.[Name], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        I.[No_] COLLATE DATABASE_DEFAULT,
        I.[Description] COLLATE DATABASE_DEFAULT,

        I.[Base Unit of Measure]
            COLLATE DATABASE_DEFAULT,

        SUM(-VE.[Sales Amount (Actual)]),
        SUM(VE.[Cost Amount (Actual)]),

        SUM(
            -VE.[Sales Amount (Actual)]
            - VE.[Cost Amount (Actual)]
        ),

        SUM(VE.[Item Ledger Entry Quantity])

    FROM
        FAKHRA_LIVE.dbo.
        [Al Fakhra Date$Value Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] VE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(VE.[Posting Date]),
                MONTH(VE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        FAKHRA_LIVE.dbo.
        [Al Fakhra Date$Item$437dbf0e-84ff-417a-965d-ed2bb9650972] I
        WITH (NOLOCK)
        ON I.[No_] = VE.[Item No_]

    OUTER APPLY
    (
        SELECT TOP (1)
            DV1.[Name]
        FROM
            FAKHRA_LIVE.dbo.
            [Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DV1
            WITH (NOLOCK)
        WHERE
            LTRIM(RTRIM(DV1.[Code]))
            =
            LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], '')))
        ORDER BY
            DV1.[Dimension Code]
    ) DV

    WHERE
        VE.[Item Ledger Entry Type] = 1
        AND VE.[Posting Date] >= @FromDate
        AND VE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) IN
        (
            '016','018','011','013-1',
            '014','011-1','015','017'
        )

    GROUP BY
        M.[Month Start],

        CASE
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END,

        LTRIM(RTRIM(ISNULL(VE.[Global Dimension 1 Code], ''))),
        ISNULL(DV.[Name], 'Unmapped'),
        I.[No_],
        I.[Description],
        I.[Base Unit of Measure]
),

ActualNormalized AS
(
    SELECT
        A.[Company],
        A.[Source Type],
        A.[Month Start],
        A.[YearMonth],

        CASE
            WHEN A.[Customer Category Code] = '1010'
                THEN N'AIRLINES'

            WHEN A.[Customer Category Code] = '1080'
                THEN N'HOTELS'

            WHEN A.[Customer Category Code] = '1150'
                THEN N'JOMARA SUPERMARKETS'

            WHEN A.[Customer Category Code] IN ('1151','1152')
                THEN N'JOMARA DISTRIBUTION'

            WHEN A.[Customer Category Code] IN ('1160','1182')
                THEN N'DUTYFREE'

            WHEN A.[Customer Category Code] IN ('1180','1181')
                THEN N'JOMARA EXPORTS'

            WHEN A.[Customer Category Code] IN
            (
                '1040','1020','1030','1060','1070',
                '1090','1100','1190','1131'
            )
                THEN N'CORPORATES & INSTS.'

            WHEN UPPER(LTRIM(RTRIM(ISNULL(A.[Division], '')))) IN
            (
                N'ECOM',
                N'ECOMMERCE',
                N'E-COMMERCE',
                N'E COMMERCE',
                N'E-COM'
            )
                THEN N'E-COMMERCE'

            WHEN UPPER(LTRIM(RTRIM(ISNULL(A.[Division], '')))) IN
            (
                N'CAFE',
                N'CAFÉ'
            )
                THEN N'CAFE'

            WHEN NULLIF(LTRIM(RTRIM(A.[Division])), '') IS NOT NULL
                THEN LTRIM(RTRIM(A.[Division]))

            WHEN NULLIF(LTRIM(RTRIM(A.[Customer Category])), '') IS NOT NULL
                THEN LTRIM(RTRIM(A.[Customer Category]))

            ELSE N'Unmapped'

        END COLLATE DATABASE_DEFAULT AS [Division],

        A.[Department Code],
        A.[Department],
        A.[Customer Category Code],
        A.[Customer Category],
        A.[SKU],
        A.[Item Description],
        A.[Base Unit of Measure],
        A.[Sales],
        A.[COGS],
        A.[GM],
        A.[Quantity]

    FROM ActualRaw A
),

BudgetRaw AS
(
    /* ============================================================
       UAE BUDGET
       ============================================================ */
    SELECT
        N'UAE' AS [Company],
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120) AS [YearMonth],

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Division],

        ISNULL(B.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT AS [Department Code],

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Department],

        SUM(
            CASE
                WHEN B.[G_L Account No_] LIKE '3%'
                     AND B.[G_L Account No_] NOT IN ('30160','30161','30162','30163','30170')   -- FIX 5: Other Income is a separate line
                    THEN -B.[Amount]
                ELSE 0
            END
        ) AS [Sales Budget],

        SUM(
            CASE
                WHEN
                (
                    JD.[Division_ID] IN ('RETAIL','CAFE','ELAN')
                    OR
                    (
                        JD.[Division_ID] IN ('E-COMMERCE','ECOM','ECOMMERCE')
                        AND B.[Global Dimension 2 Code] = '1196'
                    )
                )
                AND B.[G_L Account No_] IN
                (
                    '41011','41100','41103','41104','41105','41106',
                    '41108','41109','41121','41125','41128','41133','41138'
                )
                    THEN -B.[Amount]

                WHEN
                (
                    JD.[Division_ID] NOT IN ('RETAIL','CAFE','ELAN')
                    AND NOT
                    (
                        JD.[Division_ID] IN ('E-COMMERCE','ECOM','ECOMMERCE')
                        AND B.[Global Dimension 2 Code] = '1196'
                    )
                )
                AND B.[G_L Account No_] = '41100'
                    THEN -B.[Amount]

                ELSE 0
            END
        ) AS [COGS Budget]

    FROM
        [BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(B.[Date]),
                MONTH(B.[Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, B.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        B.[Budget Name] = @BudgetName
        AND B.[Date] >= @FromDate
        AND B.[Date] < DATEADD(DAY, 1, @BudgetToDate)   -- FIX 2

        AND
        (
            LEFT(B.[G_L Account No_], 1) = '3'
            OR B.[G_L Account No_] IN
            (
                '41011','41100','41103','41104','41105','41106',
                '41108','41109','41121','41125','41128','41133','41138'
            )
        )

        AND UPPER(LTRIM(RTRIM(JD.[Division_ID]))) IN   -- FIX 3: case/space-insensitive
        (
            'CAFE',
            'E-COMMERCE',
            'ECOM',
            'ECOMMERCE',
            'ELAN',
            'FRANCHISE',
            'FRANCHAISE',
            'RETAIL',
            'SNS'
        )

        -- FIX 4: these rows are already reported by customer category; exclude so they are counted once
        AND LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) NOT IN ('1010','1080','1150','1151','1152','1160','1182','1180','1181','1040','1020','1030','1060','1070','1090','1100','1190','1131')

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(B.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped')

    UNION ALL

    /* ============================================================
       UAE BUDGET - CUSTOMER CATEGORY
       ============================================================ */
    SELECT
        N'UAE',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        CASE
            WHEN B.[Global Dimension 1 Code] = '1010'
                THEN N'AIRLINES'
            WHEN B.[Global Dimension 1 Code] = '1080'
                THEN N'HOTELS'
            WHEN B.[Global Dimension 1 Code] = '1150'
                THEN N'JOMARA SUPERMARKETS'
            WHEN B.[Global Dimension 1 Code] IN ('1151','1152')
                THEN N'JOMARA DISTRIBUTION'
            WHEN B.[Global Dimension 1 Code] IN ('1160','1182')
                THEN N'DUTYFREE'
            WHEN B.[Global Dimension 1 Code] IN ('1180','1181')
                THEN N'JOMARA EXPORTS'
            WHEN B.[Global Dimension 1 Code] IN
            (
                '1040','1020','1030','1060','1070',
                '1090','1100','1190','1131'
            )
                THEN N'CORPORATES & INSTS.'
            ELSE N'Unmapped'
        END COLLATE DATABASE_DEFAULT,

        ISNULL(B.[Global Dimension 1 Code], '')
            COLLATE DATABASE_DEFAULT,

        CASE
            WHEN B.[Global Dimension 1 Code] = '1010'
                THEN N'AIRLINES'
            WHEN B.[Global Dimension 1 Code] = '1080'
                THEN N'HOTELS'
            WHEN B.[Global Dimension 1 Code] = '1150'
                THEN N'JOMARA SUPERMARKETS'
            WHEN B.[Global Dimension 1 Code] IN ('1151','1152')
                THEN N'JOMARA DISTRIBUTION'
            WHEN B.[Global Dimension 1 Code] IN ('1160','1182')
                THEN N'DUTYFREE'
            WHEN B.[Global Dimension 1 Code] IN ('1180','1181')
                THEN N'JOMARA EXPORTS'
            WHEN B.[Global Dimension 1 Code] IN
            (
                '1040','1020','1030','1060','1070',
                '1090','1100','1190','1131'
            )
                THEN N'CORPORATES & INSTS.'
            ELSE N'Unmapped'
        END COLLATE DATABASE_DEFAULT,

        SUM(
            CASE
                WHEN B.[G_L Account No_] LIKE '3%'
                     AND B.[G_L Account No_] NOT IN ('30160','30161','30162','30163','30170')   -- FIX 5: Other Income is a separate line
                    THEN -B.[Amount]
                ELSE 0
            END
        ),

        SUM(
            CASE
                WHEN B.[G_L Account No_] = '41100'
                    THEN -B.[Amount]
                ELSE 0
            END
        )

    FROM
        [BATEEL-UAE$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(B.[Date]),
                MONTH(B.[Date]),
                1
            )
        )
    ) M([Month Start])

    WHERE
        B.[Budget Name] = @BudgetName
        AND B.[Date] >= @FromDate
        AND B.[Date] < DATEADD(DAY, 1, @BudgetToDate)   -- FIX 2

        AND
        (
            LEFT(B.[G_L Account No_], 1) = '3'
            OR B.[G_L Account No_] = '41100'
        )

        AND B.[Global Dimension 1 Code] IN
        (
            '1010','1080','1150',
            '1151','1152',
            '1160','1182',
            '1180','1181',
            '1040','1020','1030','1060','1070',
            '1090','1100','1190','1131'
        )

    GROUP BY
        M.[Month Start],

        CASE
            WHEN B.[Global Dimension 1 Code] = '1010'
                THEN N'AIRLINES'
            WHEN B.[Global Dimension 1 Code] = '1080'
                THEN N'HOTELS'
            WHEN B.[Global Dimension 1 Code] = '1150'
                THEN N'JOMARA SUPERMARKETS'
            WHEN B.[Global Dimension 1 Code] IN ('1151','1152')
                THEN N'JOMARA DISTRIBUTION'
            WHEN B.[Global Dimension 1 Code] IN ('1160','1182')
                THEN N'DUTYFREE'
            WHEN B.[Global Dimension 1 Code] IN ('1180','1181')
                THEN N'JOMARA EXPORTS'
            WHEN B.[Global Dimension 1 Code] IN
            (
                '1040','1020','1030','1060','1070',
                '1090','1100','1190','1131'
            )
                THEN N'CORPORATES & INSTS.'
            ELSE N'Unmapped'
        END,

        ISNULL(B.[Global Dimension 1 Code], '')

    UNION ALL

    /* ============================================================
       KSA BUDGET
       ============================================================ */
    SELECT
        N'KSA',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        ISNULL(B.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT,

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        SUM(
            CASE
                WHEN B.[G_L Account No_] LIKE '3%'
                     AND B.[G_L Account No_] NOT IN ('30160','30161','30162','30163','30170')   -- FIX 5: Other Income is a separate line
                    THEN -B.[Amount]
                ELSE 0
            END
        ),

        SUM(
            CASE
                WHEN
                (
                    JD.[Division_ID] IN ('RETAIL','CAFE','ELAN')
                    OR
                    (
                        JD.[Division_ID] IN ('E-COMMERCE','ECOM','ECOMMERCE')
                        AND B.[Global Dimension 2 Code] = '3188'
                    )
                )
                AND B.[G_L Account No_] IN
                (
                    '41011','41100','41103','41104','41105','41106',
                    '41108','41109','41121','41125','41128','41133','41138'
                )
                    THEN -B.[Amount]

                WHEN
                (
                    JD.[Division_ID] NOT IN ('RETAIL','CAFE','ELAN')
                    AND NOT
                    (
                        JD.[Division_ID] IN ('E-COMMERCE','ECOM','ECOMMERCE')
                        AND B.[Global Dimension 2 Code] = '3188'
                    )
                )
                AND B.[G_L Account No_] = '41100'
                    THEN -B.[Amount]

                ELSE 0
            END
        )

    FROM
        [BATEEL-KSA$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(B.[Date]),
                MONTH(B.[Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, B.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        B.[Budget Name] = @BudgetName
        AND B.[Date] >= @FromDate
        AND B.[Date] < DATEADD(DAY, 1, @BudgetToDate)   -- FIX 2

        AND
        (
            LEFT(B.[G_L Account No_], 1) = '3'
            OR B.[G_L Account No_] IN
            (
                '41011','41100','41103','41104','41105','41106',
                '41108','41109','41121','41125','41128','41133','41138'
            )
        )

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(B.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped')

    UNION ALL

    /* ============================================================
       FAKHRA BUDGET
       ============================================================ */
    SELECT
        N'FAKHRA',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        CASE
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END COLLATE DATABASE_DEFAULT,

        LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], '')))
            COLLATE DATABASE_DEFAULT,

        ISNULL(DV.[Name], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        SUM(
            CASE
                WHEN B.[G_L Account No_] LIKE '3%'
                     AND B.[G_L Account No_] NOT IN ('30160','30161','30162','30163','30170')   -- FIX 5: Other Income is a separate line
                    THEN -B.[Amount]
                ELSE 0
            END
        ),

        SUM(
            CASE
                WHEN B.[G_L Account No_] = '41100'
                    THEN -B.[Amount]
                ELSE 0
            END
        )

    FROM
        FAKHRA_LIVE.dbo.
        [Al Fakhra Date$G_L Budget Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] B
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(B.[Date]),
                MONTH(B.[Date]),
                1
            )
        )
    ) M([Month Start])

    OUTER APPLY
    (
        SELECT TOP (1)
            DV1.[Name]

        FROM
            FAKHRA_LIVE.dbo.
            [Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DV1
            WITH (NOLOCK)

        WHERE
            LTRIM(RTRIM(DV1.[Code]))
            =
            LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], '')))

        ORDER BY
            DV1.[Dimension Code]
    ) DV

    WHERE
        B.[Budget Name] = @FakhraBudgetName
        AND B.[Date] >= @FromDate
        AND B.[Date] < DATEADD(DAY, 1, @BudgetToDate)   -- FIX 2

        AND
        (
            LEFT(B.[G_L Account No_], 1) = '3'
            OR B.[G_L Account No_] = '41100'
        )

        AND LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) IN
        (
            '016','018','011','013-1',
            '014','011-1','015','017'
        )

    GROUP BY
        M.[Month Start],

        CASE
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END,

        LTRIM(RTRIM(ISNULL(B.[Global Dimension 1 Code], ''))),
        ISNULL(DV.[Name], 'Unmapped')
),

OtherIncomeRaw AS
(
    /* ============================================================
       UAE OTHER INCOME
       ============================================================ */
    SELECT
        N'UAE' AS [Company],
        N'OTHER INCOME' AS [Source Type],
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120) AS [YearMonth],

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Division],

        ISNULL(GLE.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT AS [Department Code],

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT AS [Department],

        GLE.[G_L Account No_]
            COLLATE DATABASE_DEFAULT AS [SKU],

        ISNULL(GLA.[Name], 'Other Income')
            COLLATE DATABASE_DEFAULT AS [Item Description],

        SUM(-GLE.[Amount]) AS [Other Income]

    FROM
        [BATEEL-UAE$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] GLE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(GLE.[Posting Date]),
                MONTH(GLE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        [BATEEL-UAE$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] GLA
        WITH (NOLOCK)
        ON GLA.[No_] = GLE.[G_L Account No_]

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, GLE.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        GLE.[Posting Date] >= @FromDate
        AND GLE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND CONVERT(TIME(0), GLE.[Posting Date]) <> '23:59:59'   -- FIX 6: exclude year-end closing entries

        AND GLE.[G_L Account No_] IN
        (
            '30160',
            '30161',
            '30162',
            '30163',
            '30170'
        )

        AND UPPER(LTRIM(RTRIM(JD.[Division_ID]))) IN   -- FIX 3: case/space-insensitive
        (
            'CAFE',
            'E-COMMERCE',
            'ECOM',
            'ECOMMERCE',
            'ELAN',
            'FRANCHISE',
            'FRANCHAISE',
            'RETAIL',
            'SNS'
        )

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(GLE.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped'),
        GLE.[G_L Account No_],
        ISNULL(GLA.[Name], 'Other Income')

    UNION ALL

    /* ============================================================
       KSA OTHER INCOME
       ============================================================ */
    SELECT
        N'KSA',
        N'OTHER INCOME',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        ISNULL(JD.[Division_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        ISNULL(GLE.[Global Dimension 2 Code], '')
            COLLATE DATABASE_DEFAULT,

        ISNULL(JD.[Department_Desc], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        GLE.[G_L Account No_]
            COLLATE DATABASE_DEFAULT,

        ISNULL(GLA.[Name], 'Other Income')
            COLLATE DATABASE_DEFAULT,

        SUM(-GLE.[Amount])

    FROM
        [BATEEL-KSA$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] GLE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(GLE.[Posting Date]),
                MONTH(GLE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        [BATEEL-KSA$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] GLA
        WITH (NOLOCK)
        ON GLA.[No_] = GLE.[G_L Account No_]

    LEFT JOIN dbo.[Jedoxdept] JD
        WITH (NOLOCK)
        ON TRY_CONVERT(INT, GLE.[Global Dimension 2 Code])
           = TRY_CONVERT(INT, JD.[Navision_ID])

    WHERE
        GLE.[Posting Date] >= @FromDate
        AND GLE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND CONVERT(TIME(0), GLE.[Posting Date]) <> '23:59:59'   -- FIX 6: exclude year-end closing entries

        AND GLE.[G_L Account No_] IN
        (
            '30160',
            '30161',
            '30162',
            '30163',
            '30170'
        )

    GROUP BY
        M.[Month Start],
        ISNULL(JD.[Division_Desc], 'Unmapped'),
        ISNULL(GLE.[Global Dimension 2 Code], ''),
        ISNULL(JD.[Department_Desc], 'Unmapped'),
        GLE.[G_L Account No_],
        ISNULL(GLA.[Name], 'Other Income')

    UNION ALL

    /* ============================================================
       FAKHRA OTHER INCOME
       ============================================================ */
    SELECT
        N'FAKHRA',
        N'OTHER INCOME',
        M.[Month Start],
        CONVERT(CHAR(7), M.[Month Start], 120),

        CASE
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END COLLATE DATABASE_DEFAULT,

        LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], '')))
            COLLATE DATABASE_DEFAULT,

        ISNULL(DV.[Name], 'Unmapped')
            COLLATE DATABASE_DEFAULT,

        GLE.[G_L Account No_]
            COLLATE DATABASE_DEFAULT,

        ISNULL(GLA.[Name], 'Other Income')
            COLLATE DATABASE_DEFAULT,

        SUM(-GLE.[Amount])

    FROM
        FAKHRA_LIVE.dbo.
        [Al Fakhra Date$G_L Entry$437dbf0e-84ff-417a-965d-ed2bb9650972] GLE
        WITH (NOLOCK)

    CROSS APPLY
    (
        VALUES
        (
            DATEFROMPARTS
            (
                YEAR(GLE.[Posting Date]),
                MONTH(GLE.[Posting Date]),
                1
            )
        )
    ) M([Month Start])

    LEFT JOIN
        FAKHRA_LIVE.dbo.
        [Al Fakhra Date$G_L Account$437dbf0e-84ff-417a-965d-ed2bb9650972] GLA
        WITH (NOLOCK)
        ON GLA.[No_] = GLE.[G_L Account No_]

    OUTER APPLY
    (
        SELECT TOP (1)
            DV1.[Name]
        FROM
            FAKHRA_LIVE.dbo.
            [Al Fakhra Date$Dimension Value$437dbf0e-84ff-417a-965d-ed2bb9650972] DV1
            WITH (NOLOCK)
        WHERE
            LTRIM(RTRIM(DV1.[Code]))
            =
            LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], '')))
        ORDER BY
            DV1.[Dimension Code]
    ) DV

    WHERE
        GLE.[Posting Date] >= @FromDate
        AND GLE.[Posting Date] < DATEADD(DAY, 1, @ToDate)

        AND CONVERT(TIME(0), GLE.[Posting Date]) <> '23:59:59'   -- FIX 6: exclude year-end closing entries

        AND GLE.[G_L Account No_] IN
        (
            '30160',
            '30161',
            '30162',
            '30163',
            '30170'
        )

        AND LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) IN
        (
            '016','018','011','013-1',
            '014','011-1','015','017'
        )

    GROUP BY
        M.[Month Start],

        CASE
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) IN ('011', '013-1')
                THEN N'FARMS'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) IN ('014', '015', '018')
                THEN N'JOMARA DISTRIBUTION'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '016'
                THEN N'JOMARA EXPORTS'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '011-1'
                THEN N'JOMARA BULK'
            WHEN LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))) = '017'
                THEN N'JOMARA PRIVATE LABEL'
            ELSE N'FARMS'
        END,

        LTRIM(RTRIM(ISNULL(GLE.[Global Dimension 1 Code], ''))),
        ISNULL(DV.[Name], 'Unmapped'),
        GLE.[G_L Account No_],
        ISNULL(GLA.[Name], 'Other Income')
),

Combined AS
(
    /* ============================================================
       ACTUAL SALES ROWS
       ============================================================ */
    SELECT
        A.[Company],
        A.[Source Type],
        A.[Month Start],
        A.[YearMonth],
        A.[Division],
        A.[Department Code],
        A.[Department],
        A.[Customer Category Code],
        A.[Customer Category],
        A.[SKU],
        A.[Item Description],
        A.[Base Unit of Measure],

        SUM(A.[Sales]) AS [Sales],
        SUM(A.[COGS]) AS [COGS],
        SUM(A.[GM]) AS [GM],

        CASE
            WHEN SUM(A.[Sales]) = 0 THEN 0
            ELSE
                100.0 * SUM(A.[GM])
                / NULLIF(SUM(A.[Sales]), 0)
        END AS [GM %],

        SUM(A.[Quantity]) AS [Quantity],

        CAST(0 AS DECIMAL(38,20)) AS [Other Income],
        CAST(0 AS DECIMAL(38,20)) AS [Sales Budget],
        CAST(0 AS DECIMAL(38,20)) AS [COGS Budget],
        CAST(0 AS DECIMAL(38,20)) AS [Budget GM],
        CAST(0 AS DECIMAL(38,20)) AS [Budget GM %]

    FROM ActualNormalized A

    GROUP BY
        A.[Company],
        A.[Source Type],
        A.[Month Start],
        A.[YearMonth],
        A.[Division],
        A.[Department Code],
        A.[Department],
        A.[Customer Category Code],
        A.[Customer Category],
        A.[SKU],
        A.[Item Description],
        A.[Base Unit of Measure]

    UNION ALL

    /* ============================================================
       BUDGET ROWS
       ============================================================ */
    SELECT
        B.[Company],
        N'BUDGET',
        B.[Month Start],
        B.[YearMonth],
        B.[Division],
        B.[Department Code],
        B.[Department],

        CAST(NULL AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        CAST(N'BUDGET' AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(N'GL Budget' AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(20))
            COLLATE DATABASE_DEFAULT,

        CAST(0 AS DECIMAL(38,20)) AS [Sales],
        CAST(0 AS DECIMAL(38,20)) AS [COGS],
        CAST(0 AS DECIMAL(38,20)) AS [GM],
        CAST(0 AS DECIMAL(38,20)) AS [GM %],
        CAST(0 AS DECIMAL(38,20)) AS [Quantity],
        CAST(0 AS DECIMAL(38,20)) AS [Other Income],

        SUM(B.[Sales Budget]) AS [Sales Budget],
        SUM(B.[COGS Budget]) AS [COGS Budget],

        SUM(B.[Sales Budget])
        - SUM(B.[COGS Budget]) AS [Budget GM],

        CASE
            WHEN SUM(B.[Sales Budget]) = 0 THEN 0
            ELSE
                100.0
                * (
                    SUM(B.[Sales Budget])
                    - SUM(B.[COGS Budget])
                  )
                / NULLIF(SUM(B.[Sales Budget]), 0)
        END AS [Budget GM %]

    FROM BudgetRaw B

    GROUP BY
        B.[Company],
        B.[Month Start],
        B.[YearMonth],
        B.[Division],
        B.[Department Code],
        B.[Department]

    UNION ALL

    /* ============================================================
       OTHER INCOME ROWS
       ============================================================ */
    SELECT
        O.[Company],
        O.[Source Type],
        O.[Month Start],
        O.[YearMonth],
        O.[Division],
        O.[Department Code],
        O.[Department],

        CAST(NULL AS NVARCHAR(50))
            COLLATE DATABASE_DEFAULT,

        CAST(NULL AS NVARCHAR(100))
            COLLATE DATABASE_DEFAULT,

        O.[SKU],
        O.[Item Description],

        CAST(NULL AS NVARCHAR(20))
            COLLATE DATABASE_DEFAULT,

        CAST(0 AS DECIMAL(38,20)) AS [Sales],
        CAST(0 AS DECIMAL(38,20)) AS [COGS],
        CAST(0 AS DECIMAL(38,20)) AS [GM],
        CAST(0 AS DECIMAL(38,20)) AS [GM %],
        CAST(0 AS DECIMAL(38,20)) AS [Quantity],

        SUM(O.[Other Income]) AS [Other Income],

        CAST(0 AS DECIMAL(38,20)) AS [Sales Budget],
        CAST(0 AS DECIMAL(38,20)) AS [COGS Budget],
        CAST(0 AS DECIMAL(38,20)) AS [Budget GM],
        CAST(0 AS DECIMAL(38,20)) AS [Budget GM %]

    FROM OtherIncomeRaw O

    GROUP BY
        O.[Company],
        O.[Source Type],
        O.[Month Start],
        O.[YearMonth],
        O.[Division],
        O.[Department Code],
        O.[Department],
        O.[SKU],
        O.[Item Description]
),

Filtered AS
(
    SELECT
        C.*,

        SUM(C.[Sales]) OVER
        (
            PARTITION BY
                C.[Company],
                C.[Source Type],
                C.[Division],
                C.[SKU]
        ) AS [YTD Sales],

        SUM(C.[Other Income]) OVER
        (
            PARTITION BY
                C.[Company],
                C.[Division],
                C.[Department Code]
        ) AS [YTD Other Income],

        SUM(C.[Sales Budget]) OVER
        (
            PARTITION BY
                C.[Company],
                C.[Division],
                C.[Department Code]
        ) AS [YTD Sales Budget],

        SUM(C.[COGS Budget]) OVER
        (
            PARTITION BY
                C.[Company],
                C.[Division],
                C.[Department Code]
        ) AS [YTD COGS Budget]

    FROM Combined C
)

SELECT
    F.[Company],
    F.[Source Type],
    F.[Month Start],
    F.[YearMonth],
    F.[Division],
    F.[Department Code],
    F.[Department],
    F.[Customer Category Code],
    F.[Customer Category],

    F.[SKU],
    F.[Item Description],
    F.[Base Unit of Measure],

    /* ============================================================
       ITEM CLASSIFICATION FROM V_ITEM
       ============================================================ */
    VI.[ItemCat],
    VI.[ProdGroup],
    VI.[ItemCat3],
    VI.[ItemCat4],
    VI.[Retail Group 1],
    VI.[Retail Group 2],

    F.[Sales],
    F.[COGS],
    F.[GM],
    F.[GM %],
    F.[Quantity],
    F.[Other Income],

    F.[Sales Budget],
    F.[COGS Budget],
    F.[Budget GM],
    F.[Budget GM %]

FROM Filtered F

LEFT JOIN dbo.[V_Item] VI
    ON VI.[No_] COLLATE DATABASE_DEFAULT
       = F.[SKU] COLLATE DATABASE_DEFAULT

WHERE
    ISNULL(F.[YTD Sales], 0) <> 0
    OR ISNULL(F.[YTD Other Income], 0) <> 0
    OR ISNULL(F.[YTD Sales Budget], 0) <> 0
    OR ISNULL(F.[YTD COGS Budget], 0) <> 0

ORDER BY
    F.[Month Start],
    F.[Company],
    F.[Source Type],
    F.[Division],
    F.[Department],
    F.[Customer Category],
    F.[SKU];
