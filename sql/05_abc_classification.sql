/* ============================================================================
   05_abc_classification.sql
   Aftermarket RIIE  |  Inventory Optimization layer
   Purpose: ABC classification of SKUs by revenue, PARTITIONED BY CATEGORY.
            This query GENERATES the classification (the source system's
            abc_class column is empty), making it the system of record for
            inventory tiering.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sku_master: sku_id, category   (abc_class exists but is EMPTY in source)
     sales_history: sku_id, revenue

   NOTE: sku_master.abc_class is unpopulated (like rfm_segment and
   expected_revenue), so there is no reference to validate against. Rather than
   check a classification, this query produces the authoritative one.

   BATCHING: GO separators rebuild #abc before any SELECT reads it, so a stale
   #abc from a prior run cannot bind to the wrong schema at compile time.

   METHOD:
     - Basis = total revenue (transparent, standard).
     - Partition = category (important SKUs judged within their own category).
     - Thresholds: cumulative revenue <=80% = A, <=95% = B, else C.
     - All master SKUs kept (LEFT JOIN); zero-sales SKUs fall to C.

   OUTPUT:
     - Result set 1 = per-SKU classification (the tiering table).
     - Result set 2 = A/B/C distribution per category. Validation = the Pareto
       signature: A should be a SMALL share of SKUs but ~80% of revenue.
   ============================================================================ */

IF OBJECT_ID('tempdb..#abc') IS NOT NULL DROP TABLE #abc;
GO

WITH sku_cat_rev AS (
    -- Total revenue per SKU (all master SKUs retained; unsold -> 0)
    SELECT
        sm.sku_id,
        sm.category,
        COALESCE(SUM(sh.revenue), 0) AS total_revenue
    FROM dbo.sku_master sm
    LEFT JOIN dbo.sales_history sh
        ON sh.sku_id = sm.sku_id
    GROUP BY sm.sku_id, sm.category
),
ranked AS (
    SELECT
        sku_id,
        category,
        total_revenue,
        SUM(total_revenue) OVER (PARTITION BY category) AS category_total,
        SUM(total_revenue) OVER (
            PARTITION BY category
            ORDER BY total_revenue DESC, sku_id          -- sku_id breaks ties deterministically
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY category
            ORDER BY total_revenue DESC, sku_id
        ) AS rank_in_category
    FROM sku_cat_rev
)
SELECT
    sku_id,
    category,
    total_revenue,
    rank_in_category,
    CAST(cumulative_revenue * 100.0 / NULLIF(category_total, 0) AS DECIMAL(7, 4))
        AS cumulative_pct_in_category,
    CASE
        WHEN cumulative_revenue * 100.0 / NULLIF(category_total, 0) <= 80.0 THEN 'A'
        WHEN cumulative_revenue * 100.0 / NULLIF(category_total, 0) <= 95.0 THEN 'B'
        ELSE 'C'
    END AS abc_class
INTO #abc
FROM ranked;
GO

/* ---- Result set 1: per-SKU classification (the tiering table) -------------- */
SELECT
    sku_id,
    category,
    total_revenue,
    rank_in_category,
    cumulative_pct_in_category,
    abc_class
FROM #abc
ORDER BY category, rank_in_category;
GO

/* ---- Result set 2: A/B/C distribution per category ------------------------- */
/* Validation = Pareto signature: A is a small % of SKUs but ~80% of revenue.   */
SELECT
    category,
    abc_class,
    COUNT(*) AS sku_count,
    CAST(COUNT(*) * 100.0
         / SUM(COUNT(*)) OVER (PARTITION BY category) AS DECIMAL(5, 2)) AS pct_of_skus,
    SUM(total_revenue) AS class_revenue,
    CAST(SUM(total_revenue) * 100.0
         / SUM(SUM(total_revenue)) OVER (PARTITION BY category) AS DECIMAL(5, 2)) AS pct_of_category_revenue
FROM #abc
GROUP BY category, abc_class
ORDER BY category, abc_class;
