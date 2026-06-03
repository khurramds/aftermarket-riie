/* ============================================================================
   08_return_rate.sql
   Aftermarket RIIE  |  Inventory Optimization layer
   Purpose: Return rate by category (value + units) and root-cause reasons.
            This is where returns are accounted for -- queries 01-02 used gross
            revenue and deferred the return drag to here.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history: sku_id, revenue, units_shipped
     returns: sku_id, units_returned, return_value, return_reason, handling_cost
     sku_master: sku_id, category

   METHOD:
     - Aggregate sales and returns per SKU, roll up to category (no fan-out:
       each SKU appears once in sku_master).
     - Result set 1 = return rate by value and units, per category + overall.
     - Result set 2 = return reasons ranked by value, with handling cost.
   ============================================================================ */

/* ---- Result set 1: return rate by category (+ overall) --------------------- */
WITH sales_agg AS (
    SELECT sku_id, SUM(revenue) AS revenue, SUM(units_shipped) AS units_sold
    FROM dbo.sales_history
    GROUP BY sku_id
),
returns_agg AS (
    SELECT
        sku_id,
        SUM(return_value)   AS return_value,
        SUM(units_returned) AS units_returned,
        SUM(handling_cost)  AS handling_cost
    FROM dbo.returns
    GROUP BY sku_id
)
SELECT
    COALESCE(sm.category, '** OVERALL **') AS category,
    SUM(ISNULL(s.revenue, 0))        AS revenue,
    SUM(ISNULL(r.return_value, 0))   AS return_value,
    CAST(SUM(ISNULL(r.return_value, 0)) * 100.0
         / NULLIF(SUM(ISNULL(s.revenue, 0)), 0) AS DECIMAL(5, 2)) AS return_rate_value_pct,
    SUM(ISNULL(s.units_sold, 0))     AS units_sold,
    SUM(ISNULL(r.units_returned, 0)) AS units_returned,
    CAST(SUM(ISNULL(r.units_returned, 0)) * 100.0
         / NULLIF(SUM(ISNULL(s.units_sold, 0)), 0) AS DECIMAL(5, 2)) AS return_rate_unit_pct,
    SUM(ISNULL(r.handling_cost, 0))  AS total_handling_cost
FROM dbo.sku_master sm
LEFT JOIN sales_agg   s ON s.sku_id = sm.sku_id
LEFT JOIN returns_agg r ON r.sku_id = sm.sku_id
GROUP BY ROLLUP(sm.category)
ORDER BY GROUPING(sm.category), return_rate_value_pct DESC;
GO

/* ---- Result set 2: why product comes back (reason breakdown) --------------- */
SELECT
    return_reason,
    COUNT(*)            AS return_lines,
    SUM(units_returned) AS units_returned,
    SUM(return_value)   AS return_value,
    CAST(SUM(return_value) * 100.0
         / SUM(SUM(return_value)) OVER () AS DECIMAL(5, 2)) AS pct_of_return_value,
    SUM(handling_cost)  AS handling_cost
FROM dbo.returns
GROUP BY return_reason
ORDER BY return_value DESC;
