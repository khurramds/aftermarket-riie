/* ============================================================================
   01_revenue_trend.sql
   Aftermarket RIIE  |  Commercial Intelligence layer
   Purpose: Monthly revenue by category with year-over-year (YoY) comparison.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns (sales_history):
     order_date  -> demand date used for the trend (NOT ship_date)
     revenue     -> pre-computed extended revenue (decimal)
   Grouping dimension: sku_master.category

   Date choice: order_date anchors the trend to when demand occurred.
   ship_date answers a fulfillment question and is left for the fill-rate query.

   Design note: LAG(revenue, 12) means "12 ROWS back", not "12 months back".
   A gap-free month spine (calendar x category) is built first so that 12 rows
   back is always exactly the same month one year prior, even for categories
   that had a zero-sales month.
   ============================================================================ */

WITH bounds AS (
    -- First and last month present in the fact table
    SELECT
        MIN(DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)) AS min_m,
        MAX(DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)) AS max_m
    FROM dbo.sales_history
),
month_spine AS (
    -- Recursive calendar of month-start dates from min_m to max_m
    SELECT min_m AS month_start, max_m
    FROM bounds
    UNION ALL
    SELECT DATEADD(MONTH, 1, month_start), max_m
    FROM month_spine
    WHERE DATEADD(MONTH, 1, month_start) <= max_m
),
categories AS (
    SELECT DISTINCT category
    FROM dbo.sku_master
    WHERE category IS NOT NULL
),
spine AS (
    -- One row per category per month: guarantees no gaps for LAG(12)
    SELECT c.category, m.month_start
    FROM categories c
    CROSS JOIN month_spine m
),
category_month AS (
    -- Actual revenue aggregated to category x month, anchored on order_date
    SELECT
        sm.category,
        DATEFROMPARTS(YEAR(sh.order_date), MONTH(sh.order_date), 1) AS month_start,
        SUM(sh.revenue) AS revenue
    FROM dbo.sales_history sh
    INNER JOIN dbo.sku_master sm
        ON sm.sku_id = sh.sku_id
    GROUP BY
        sm.category,
        DATEFROMPARTS(YEAR(sh.order_date), MONTH(sh.order_date), 1)
),
joined AS (
    -- Left-join real revenue onto the complete spine; missing months -> 0
    SELECT
        sp.category,
        sp.month_start,
        COALESCE(cm.revenue, 0) AS revenue
    FROM spine sp
    LEFT JOIN category_month cm
        ON cm.category    = sp.category
       AND cm.month_start = sp.month_start
),
lagged AS (
    SELECT
        category,
        month_start,
        revenue,
        LAG(revenue, 12) OVER (
            PARTITION BY category
            ORDER BY month_start
        ) AS revenue_prior_year
    FROM joined
)
SELECT
    category,
    month_start,
    YEAR(month_start)               AS sales_year,
    MONTH(month_start)              AS sales_month,
    revenue,
    revenue_prior_year,
    revenue - revenue_prior_year    AS yoy_change,
    CASE
        WHEN revenue_prior_year > 0
        THEN CAST((revenue - revenue_prior_year) * 100.0
                  / revenue_prior_year AS DECIMAL(10, 2))
        ELSE NULL   -- NULL where there is no comparable prior-year month yet
    END                             AS yoy_pct
FROM lagged
ORDER BY category, month_start
OPTION (MAXRECURSION 1000);   -- supports >100 months of history if ever needed
