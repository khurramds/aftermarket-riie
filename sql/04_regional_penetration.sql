/* ============================================================================
   04_regional_penetration.sql
   Aftermarket RIIE  |  Commercial Intelligence layer
   Purpose: Regional revenue normalized by market size (registered vehicles)
            to expose under-penetrated "white space" regions.
   Engine:  SQL Server 2025 (T-SQL)  |  DB: aftermarket_db  |  Instance: KHURRAM_PC

   SCHEMA-CONFIRMED columns:
     sales_history: state_code, revenue
     location_master: state_code, region, registered_vehicles, population
   6-region scheme: Midwest, Northeast, Plains, Southeast, Southwest, West.

   NOTE: location_master.expected_revenue is empty in this dataset, so a true
   actual-vs-expected penetration index is not computable. We normalize on
   registered_vehicles instead -- a period-neutral, market-size-fair metric.

   CORRECTNESS NOTE (fan-out): registered_vehicles / population are STATE-grain
   dimension attributes, aggregated in their OWN cte (region_market) and joined
   to sales totals on region -- never summed across fact rows (which would
   multiply them by transaction count).
   ============================================================================ */

WITH region_market AS (
    -- Market potential per region (location dimension, aggregated independently)
    SELECT
        region,
        SUM(registered_vehicles) AS registered_vehicles,
        SUM(population)          AS population
    FROM dbo.location_master
    GROUP BY region
),
region_actual AS (
    -- Actual revenue per region (sales fact, mapped to region via state_code)
    SELECT
        lm.region,
        SUM(sh.revenue) AS actual_revenue
    FROM dbo.sales_history sh
    INNER JOIN dbo.location_master lm
        ON lm.state_code = sh.state_code
    GROUP BY lm.region
),
combined AS (
    SELECT
        rm.region,
        ra.actual_revenue,
        rm.registered_vehicles,
        rm.population,
        SUM(ra.actual_revenue) OVER () AS grand_total_actual
    FROM region_market rm
    INNER JOIN region_actual ra
        ON ra.region = rm.region
)
SELECT
    region,
    actual_revenue,
    registered_vehicles,
    population,
    CAST(actual_revenue * 100.0  / grand_total_actual            AS DECIMAL(7, 4))  AS pct_of_total_revenue,
    CAST(actual_revenue * 1000.0 / NULLIF(registered_vehicles, 0) AS DECIMAL(12, 2)) AS revenue_per_1k_vehicles,
    -- Rank 1 = strongest market capture; the LAST rows are the white-space targets
    RANK() OVER (
        ORDER BY actual_revenue * 1.0 / NULLIF(registered_vehicles, 0) DESC
    ) AS penetration_rank
FROM combined
ORDER BY penetration_rank;
