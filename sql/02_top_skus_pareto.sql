/* ============================================================================
   02_top_skus_pareto.sql
   Aftermarket RIIE  |  Commercial Intelligence layer
   Purpose: Rank SKUs by revenue and compute Pareto (80/20) contribution.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history.sku_id, sales_history.revenue, sales_history.units_shipped
     sku_master.sku_id, sku_master.category

   Scope: COMPANY-WIDE ranking (the "vital few" SKUs overall).
          ABC-by-category is handled separately in 05_abc_classification.sql.

   Revenue basis: gross revenue (returns netted separately in 08_return_rate.sql).
   ============================================================================ */

WITH sku_revenue AS (
    -- One row per SKU: total revenue and units over the full period
    SELECT
        sh.sku_id,
        sm.category,
        SUM(sh.revenue)        AS total_revenue,
        SUM(sh.units_shipped)  AS total_units
    FROM dbo.sales_history sh
    INNER JOIN dbo.sku_master sm
        ON sm.sku_id = sh.sku_id
    GROUP BY sh.sku_id, sm.category
),
ranked AS (
    SELECT
        sku_id,
        category,
        total_revenue,
        total_units,
        ROW_NUMBER() OVER (ORDER BY total_revenue DESC)        AS revenue_rank,
        SUM(total_revenue) OVER ()                             AS grand_total_revenue,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                      AS cumulative_revenue
    FROM sku_revenue
)
SELECT
    revenue_rank,
    sku_id,
    category,
    total_units,
    total_revenue,
    CAST(total_revenue   * 100.0 / grand_total_revenue AS DECIMAL(7, 4)) AS pct_of_total,
    CAST(cumulative_revenue * 100.0 / grand_total_revenue AS DECIMAL(5, 2)) AS cumulative_pct,
    CASE
        WHEN cumulative_revenue * 100.0 / grand_total_revenue <= 80.0
        THEN 'A - Vital few (top 80%)'
        ELSE 'B - Trivial many (bottom 20%)'
    END AS pareto_segment
FROM ranked
ORDER BY revenue_rank;
