/* =====================================================================
   Aftermarket RIIE  -  02_foreign_keys.sql
   Drops any existing foreign keys, then (re)creates all 7 cleanly.
   Safe to run any number of times. Run after data is loaded.
   ===================================================================== */

USE aftermarket_db;
GO

-- 1. Drop FKs if they already exist (from an earlier partial run)
IF OBJECT_ID('dbo.fk_sales_sku','F')      IS NOT NULL ALTER TABLE dbo.sales_history      DROP CONSTRAINT fk_sales_sku;
IF OBJECT_ID('dbo.fk_sales_customer','F') IS NOT NULL ALTER TABLE dbo.sales_history      DROP CONSTRAINT fk_sales_customer;
IF OBJECT_ID('dbo.fk_sales_state','F')    IS NOT NULL ALTER TABLE dbo.sales_history      DROP CONSTRAINT fk_sales_state;
IF OBJECT_ID('dbo.fk_returns_txn','F')      IS NOT NULL ALTER TABLE dbo.returns          DROP CONSTRAINT fk_returns_txn;
IF OBJECT_ID('dbo.fk_returns_sku','F')      IS NOT NULL ALTER TABLE dbo.returns          DROP CONSTRAINT fk_returns_sku;
IF OBJECT_ID('dbo.fk_returns_customer','F') IS NOT NULL ALTER TABLE dbo.returns          DROP CONSTRAINT fk_returns_customer;
IF OBJECT_ID('dbo.fk_inv_sku','F')          IS NOT NULL ALTER TABLE dbo.inventory_snapshot DROP CONSTRAINT fk_inv_sku;
GO

-- 2. (Re)create all 7 foreign keys
ALTER TABLE dbo.sales_history ADD
    CONSTRAINT fk_sales_sku      FOREIGN KEY (sku_id)      REFERENCES dbo.sku_master(sku_id),
    CONSTRAINT fk_sales_customer FOREIGN KEY (customer_id) REFERENCES dbo.customer_master(customer_id),
    CONSTRAINT fk_sales_state    FOREIGN KEY (state_code)  REFERENCES dbo.location_master(state_code);

ALTER TABLE dbo.returns ADD
    CONSTRAINT fk_returns_txn      FOREIGN KEY (transaction_id) REFERENCES dbo.sales_history(transaction_id),
    CONSTRAINT fk_returns_sku      FOREIGN KEY (sku_id)         REFERENCES dbo.sku_master(sku_id),
    CONSTRAINT fk_returns_customer FOREIGN KEY (customer_id)    REFERENCES dbo.customer_master(customer_id);

ALTER TABLE dbo.inventory_snapshot ADD
    CONSTRAINT fk_inv_sku FOREIGN KEY (sku_id) REFERENCES dbo.sku_master(sku_id);
GO

PRINT 'All 7 foreign keys created. Schema and data load complete.';
GO
