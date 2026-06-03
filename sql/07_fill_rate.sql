/* ============================================================================
   07_fill_rate.sql
   Aftermarket RIIE  |  Inventory Optimization layer
   Purpose: Line fill rate vs the 97% service-level guardrail.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history: sku_id, units_ordered, units_shipped
     sku_master: sku_id, category

   METHOD:
     - Fill rate = units_shipped / units_ordered (standard line fill rate).
     - Guardrail = 97%. Result set 1 = per-SKU (worst first); result set 2 =
       category + overall (ROLLUP).
     - Complementary lens: inventory_snapshot.stockout_flag (encoding TBD; run
       SELECT DISTINCT stockout_flag FROM dbo.inventory_snapshot; to confirm,
       then it can be added as a stockout-frequency metric).
   ============================================================================ */

/* ---- Result set 1: per-SKU fill rate (worst first) ------------------------- */
SELECT
    sh.sku_id,
    sm.category,
    SUM(sh.units_ordered) AS units_ordered,
    SUM(sh.units_shipped) AS units_shipped,
    CAST(SUM(sh.units_shipped) * 100.0 / NULLIF(SUM(sh.units_ordered), 0) AS DECIMAL(5, 2)) AS fill_rate_pct,
    CASE
        WHEN SUM(sh.units_shipped) * 100.0 / NULLIF(SUM(sh.units_ordered), 0) < 97.0
        THEN 'BELOW 97% guardrail'
        ELSE 'OK'
    END AS guardrail_status
FROM dbo.sales_history sh
INNER JOIN dbo.sku_master sm ON sm.sku_id = sh.sku_id
GROUP BY sh.sku_id, sm.category
ORDER BY fill_rate_pct ASC;
GO

/* ---- Result set 2: category + overall fill rate vs guardrail --------------- */
SELECT
    COALESCE(sm.category, '** OVERALL **') AS category,
    SUM(sh.units_ordered) AS units_ordered,
    SUM(sh.units_shipped) AS units_shipped,
    CAST(SUM(sh.units_shipped) * 100.0 / NULLIF(SUM(sh.units_ordered), 0) AS DECIMAL(5, 2)) AS fill_rate_pct,
    CASE
        WHEN SUM(sh.units_shipped) * 100.0 / NULLIF(SUM(sh.units_ordered), 0) < 97.0
        THEN 'BELOW 97% guardrail'
        ELSE 'OK'
    END AS guardrail_status
FROM dbo.sales_history sh
INNER JOIN dbo.sku_master sm ON sm.sku_id = sh.sku_id
GROUP BY ROLLUP(sm.category)
ORDER BY GROUPING(sm.category), fill_rate_pct;
