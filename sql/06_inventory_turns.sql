/* ============================================================================
   06_inventory_turns.sql
   Aftermarket RIIE  |  Inventory Optimization layer
   Purpose: Inventory turnover and days-on-hand per SKU.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history: sku_id, order_date, units_shipped
     sku_master: sku_id, category, unit_cost
     inventory_snapshot: sku_id, inventory_value, units_on_hand, days_on_hand

   METHOD:
     - COGS = units_shipped * unit_cost, annualized by the actual sales span
       (so a multi-year window does not distort turns).
     - Turns = annual COGS / average inventory value (both at COST basis).
     - days_on_hand_calc = 365 / turns; days_on_hand_reported = snapshot avg
       (shown side by side as a cross-check).
   ============================================================================ */

WITH period AS (
    SELECT DATEDIFF(DAY, MIN(order_date), MAX(order_date)) + 1 AS span_days
    FROM dbo.sales_history
),
sku_cogs AS (
    SELECT sh.sku_id, SUM(sh.units_shipped * sm.unit_cost) AS total_cogs
    FROM dbo.sales_history sh
    INNER JOIN dbo.sku_master sm ON sm.sku_id = sh.sku_id
    GROUP BY sh.sku_id
),
sku_inv AS (
    SELECT
        sku_id,
        AVG(CAST(inventory_value AS DECIMAL(18, 4))) AS avg_inventory_value,
        AVG(CAST(units_on_hand   AS DECIMAL(18, 4))) AS avg_units_on_hand,
        AVG(CAST(days_on_hand    AS DECIMAL(18, 4))) AS avg_days_on_hand_reported
    FROM dbo.inventory_snapshot
    GROUP BY sku_id
),
metrics AS (
    SELECT
        sm.sku_id,
        sm.category,
        CAST(ISNULL(c.total_cogs, 0) * 365.0 / p.span_days AS DECIMAL(18, 2)) AS annual_cogs,
        i.avg_inventory_value,
        i.avg_days_on_hand_reported
    FROM dbo.sku_master sm
    LEFT JOIN sku_cogs c ON c.sku_id = sm.sku_id
    LEFT JOIN sku_inv  i ON i.sku_id = sm.sku_id
    CROSS JOIN period p
)
SELECT
    sku_id,
    category,
    annual_cogs,
    avg_inventory_value,
    CAST(annual_cogs / NULLIF(avg_inventory_value, 0)        AS DECIMAL(10, 2)) AS inventory_turns,
    CAST(365.0 * avg_inventory_value / NULLIF(annual_cogs, 0) AS DECIMAL(10, 1)) AS days_on_hand_calc,
    CAST(avg_days_on_hand_reported                           AS DECIMAL(10, 1)) AS days_on_hand_reported
FROM metrics
ORDER BY inventory_turns DESC;
