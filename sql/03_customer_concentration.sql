/* ============================================================================
   03_customer_concentration.sql
   Aftermarket RIIE  |  Commercial Intelligence layer
   Purpose: Rank customers by revenue; measure concentration / dependency risk.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history: customer_id, transaction_id, revenue
     customer_master: customer_id, customer_name, customer_type, region

   NOTE: customer_master.rfm_segment is empty in this dataset, so it is omitted
   (an all-NULL column adds no value). RFM segmentation would be a separate
   computed module derived from sales_history recency/frequency/monetary.

   Revenue basis: gross revenue (returns netted separately in 08_return_rate.sql).
   Read concentration directly: cumulative_pct at revenue_rank = 10 is the
   "top-10 accounts = X% of revenue" KPI.
   ============================================================================ */

WITH customer_revenue AS (
    -- One row per customer: total revenue and true order count
    SELECT
        sh.customer_id,
        cm.customer_name,
        cm.customer_type,
        cm.region,
        SUM(sh.revenue)                   AS total_revenue,
        COUNT(DISTINCT sh.transaction_id) AS order_count
    FROM dbo.sales_history sh
    INNER JOIN dbo.customer_master cm
        ON cm.customer_id = sh.customer_id
    GROUP BY
        sh.customer_id, cm.customer_name, cm.customer_type, cm.region
),
ranked AS (
    SELECT
        customer_id,
        customer_name,
        customer_type,
        region,
        order_count,
        total_revenue,
        ROW_NUMBER() OVER (ORDER BY total_revenue DESC)  AS revenue_rank,
        SUM(total_revenue) OVER ()                       AS grand_total,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                                AS cumulative_revenue
    FROM customer_revenue
)
SELECT
    revenue_rank,
    customer_id,
    customer_name,
    customer_type,
    region,
    order_count,
    total_revenue,
    CAST(total_revenue      * 100.0 / grand_total AS DECIMAL(7, 4)) AS pct_of_total,
    CAST(cumulative_revenue * 100.0 / grand_total AS DECIMAL(7, 4)) AS cumulative_pct,
    CASE
        WHEN cumulative_revenue * 100.0 / grand_total <= 50.0
            THEN 'Tier 1 - Key accounts (first 50% of revenue)'
        WHEN cumulative_revenue * 100.0 / grand_total <= 80.0
            THEN 'Tier 2 - Mid accounts'
        ELSE 'Tier 3 - Long tail'
    END AS concentration_tier
FROM ranked
ORDER BY revenue_rank;
