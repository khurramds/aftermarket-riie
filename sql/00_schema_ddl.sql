/* =====================================================================
   Aftermarket RIIE  -  00_schema_ddl.sql
   Day 1, Block 4  -  Database + 7-table schema (Section 3)

   Run order:  1) this file (00_schema_ddl.sql)
               2) 01_load_data.sql   (loads CSVs, then adds foreign keys)

   Server   : KHURRAM_PC   (Windows Auth)
   Database : aftermarket_db

   TYPE NOTES (why these choices):
     - All *_id keys are VARCHAR(20): synthetic IDs may be alphanumeric
       (e.g. 'SKU-00001'). VARCHAR loads any ID format without error.
       If your generator emitted pure integers you can tighten to INT later.
     - is_private_label / restockable / stockout_flag are VARCHAR(5)
       because pandas writes booleans as the text 'True'/'False'.
     - The 6 analytical columns (abc_class, xyz_class, composite_score,
       tier_recommendation, rfm_segment, churn_probability) are NULL here.
       They are EMPTY in the CSVs on purpose and get filled by the Day 3
       Python engine. Empty CSV fields load as NULL into these columns.
   ===================================================================== */

-------------------------------------------------------------------------
-- 0. Create database
-------------------------------------------------------------------------
IF DB_ID('aftermarket_db') IS NULL
    CREATE DATABASE aftermarket_db;
GO

USE aftermarket_db;
GO

-------------------------------------------------------------------------
-- 1. Drop existing tables (child -> parent) so the script is re-runnable
-------------------------------------------------------------------------
IF OBJECT_ID('dbo.inventory_snapshot','U') IS NOT NULL DROP TABLE dbo.inventory_snapshot;
IF OBJECT_ID('dbo.returns','U')            IS NOT NULL DROP TABLE dbo.returns;
IF OBJECT_ID('dbo.sales_history','U')      IS NOT NULL DROP TABLE dbo.sales_history;
IF OBJECT_ID('dbo.sku_master','U')         IS NOT NULL DROP TABLE dbo.sku_master;
IF OBJECT_ID('dbo.customer_master','U')    IS NOT NULL DROP TABLE dbo.customer_master;
IF OBJECT_ID('dbo.supplier_master','U')    IS NOT NULL DROP TABLE dbo.supplier_master;
IF OBJECT_ID('dbo.location_master','U')    IS NOT NULL DROP TABLE dbo.location_master;
GO

-------------------------------------------------------------------------
-- 2. location_master  (48)  -- real FHWA 2023 vehicle-registration data
-------------------------------------------------------------------------
CREATE TABLE dbo.location_master (
    state_code          VARCHAR(2)    NOT NULL,
    state_name          VARCHAR(40)   NULL,
    region              VARCHAR(30)   NULL,
    market_tier         VARCHAR(20)   NULL,
    registered_vehicles BIGINT        NULL,
    population          BIGINT        NULL,
    vehicles_per_capita DECIMAL(10,4) NULL,
    actual_revenue_ly   DECIMAL(14,2) NULL,
    expected_revenue    DECIMAL(14,2) NULL,
    penetration_pct     DECIMAL(7,4)  NULL,
    CONSTRAINT pk_location_master PRIMARY KEY (state_code)
);
GO

-------------------------------------------------------------------------
-- 3. supplier_master  (45)
-------------------------------------------------------------------------
CREATE TABLE dbo.supplier_master (
    supplier_id          VARCHAR(20)   NOT NULL,
    supplier_name        VARCHAR(120)  NULL,
    country_of_origin    VARCHAR(50)   NULL,
    lead_time_days       INT           NULL,
    quality_score        DECIMAL(7,4)  NULL,
    tariff_exposure      VARCHAR(20)    NULL,
    min_order_qty        INT           NULL,
    on_time_delivery_pct DECIMAL(7,4)  NULL,
    CONSTRAINT pk_supplier_master PRIMARY KEY (supplier_id)
);
GO

-------------------------------------------------------------------------
-- 4. customer_master  (200)  -- rfm_segment + churn_probability: Day 3
-------------------------------------------------------------------------
CREATE TABLE dbo.customer_master (
    customer_id        VARCHAR(20)   NOT NULL,
    customer_name      VARCHAR(120)  NULL,
    customer_type      VARCHAR(40)   NULL,
    primary_state      VARCHAR(2)    NULL,
    region             VARCHAR(30)   NULL,
    account_manager    VARCHAR(80)   NULL,
    credit_terms       VARCHAR(30)   NULL,
    customer_since     DATE          NULL,
    credit_limit       DECIMAL(12,2) NULL,
    rfm_segment        VARCHAR(30)   NULL,   -- filled by Day 3 Python engine
    churn_probability  DECIMAL(7,4)  NULL,   -- filled by Day 3 Python engine
    CONSTRAINT pk_customer_master PRIMARY KEY (customer_id)
);
GO

-------------------------------------------------------------------------
-- 5. sku_master  (500)  -- abc/xyz/composite/tier: Day 3
-------------------------------------------------------------------------
CREATE TABLE dbo.sku_master (
    sku_id              VARCHAR(20)   NOT NULL,
    category            VARCHAR(50)   NULL,
    unit_cost           DECIMAL(10,2) NULL,
    list_price          DECIMAL(10,2) NULL,
    gross_margin_pct    DECIMAL(7,4)  NULL,
    fitment_breadth     INT           NULL,
    supplier_count      INT           NULL,
    is_private_label    VARCHAR(5)    NULL,   -- 'True' / 'False'
    abc_class           VARCHAR(1)    NULL,   -- filled by Day 3 Python engine
    xyz_class           VARCHAR(1)    NULL,   -- filled by Day 3 Python engine
    composite_score     DECIMAL(10,4) NULL,   -- filled by Day 3 Python engine
    tier_recommendation VARCHAR(30)   NULL,   -- filled by Day 3 Python engine
    CONSTRAINT pk_sku_master PRIMARY KEY (sku_id)
);
GO

-------------------------------------------------------------------------
-- 6. sales_history  (~750,000)
-------------------------------------------------------------------------
CREATE TABLE dbo.sales_history (
    transaction_id  VARCHAR(20)   NOT NULL,
    order_date      DATE          NULL,
    ship_date       DATE          NULL,
    sku_id          VARCHAR(20)   NOT NULL,
    customer_id     VARCHAR(20)   NOT NULL,
    state_code      VARCHAR(2)    NOT NULL,
    units_ordered   INT           NULL,
    units_shipped   INT           NULL,
    unit_price      DECIMAL(10,2) NULL,
    discount_pct    DECIMAL(7,4)  NULL,
    revenue         DECIMAL(12,2) NULL,
    order_channel   VARCHAR(30)   NULL,
    CONSTRAINT pk_sales_history PRIMARY KEY (transaction_id)
);
GO

-------------------------------------------------------------------------
-- 7. returns  (~37,500)
-------------------------------------------------------------------------
CREATE TABLE dbo.returns (
    return_id       VARCHAR(20)   NOT NULL,
    transaction_id  VARCHAR(20)   NOT NULL,
    sku_id          VARCHAR(20)   NOT NULL,
    customer_id     VARCHAR(20)   NOT NULL,
    return_date     DATE          NULL,
    units_returned  INT           NULL,
    return_reason   VARCHAR(30)   NULL,
    return_value    DECIMAL(12,2) NULL,
    restockable     VARCHAR(5)    NULL,   -- 'True' / 'False'
    handling_cost   DECIMAL(10,2) NULL,
    CONSTRAINT pk_returns PRIMARY KEY (return_id)
);
GO

-------------------------------------------------------------------------
-- 8. inventory_snapshot  (~26,000)
-------------------------------------------------------------------------
CREATE TABLE dbo.inventory_snapshot (
    snapshot_id     VARCHAR(20)   NOT NULL,
    week_ending     DATE          NULL,
    sku_id          VARCHAR(20)   NOT NULL,
    units_on_hand   INT           NULL,
    units_on_order  INT           NULL,
    reorder_point   INT           NULL,
    reorder_qty     INT           NULL,
    days_on_hand    DECIMAL(10,2) NULL,
    inventory_value DECIMAL(12,2) NULL,
    stockout_flag   VARCHAR(5)    NULL,   -- 'True' / 'False'
    CONSTRAINT pk_inventory_snapshot PRIMARY KEY (snapshot_id)
);
GO

PRINT 'Schema created: aftermarket_db with 7 tables. Next: run 01_load_data.sql';
GO
