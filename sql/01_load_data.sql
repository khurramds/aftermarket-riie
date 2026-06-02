/* =====================================================================
   Aftermarket RIIE  -  01_load_data.sql
   Day 1, Block 4  -  Load 7 CSVs into aftermarket_db, then add FKs

   Run AFTER 00_schema_ddl.sql.

   Method: BULK INSERT with FORMAT='CSV' (SQL Server 2017+; you are on 2025).
     - FORMAT='CSV' correctly handles the header row, quoted fields, and
       commas inside quoted text (e.g. customer names), and CRLF endings.
     - FIRSTROW = 2 skips the pandas header row.
     - Empty fields (the unfilled analytical columns) load as NULL.

   Load order is parent -> child so the foreign keys at the bottom hold.
   FKs are added AFTER the data is in (standard ETL pattern): a fast,
   set-based load first, integrity enforced once at the end.

   >>> Edit @path below if your repo is not at C:\Projects\aftermarket-riie
   ===================================================================== */

USE aftermarket_db;
GO

-- Optional: clear tables so this script can be re-run (child -> parent)
DELETE FROM dbo.inventory_snapshot;
DELETE FROM dbo.returns;
DELETE FROM dbo.sales_history;
DELETE FROM dbo.sku_master;
DELETE FROM dbo.customer_master;
DELETE FROM dbo.supplier_master;
DELETE FROM dbo.location_master;
GO

-------------------------------------------------------------------------
-- LOAD  (parent tables first)
-------------------------------------------------------------------------
BULK INSERT dbo.location_master
FROM 'C:\Projects\aftermarket-riie\data\location_master.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

BULK INSERT dbo.supplier_master
FROM 'C:\Projects\aftermarket-riie\data\supplier_master.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

BULK INSERT dbo.customer_master
FROM 'C:\Projects\aftermarket-riie\data\customer_master.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

BULK INSERT dbo.sku_master
FROM 'C:\Projects\aftermarket-riie\data\sku_master.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

-- child tables
BULK INSERT dbo.sales_history
FROM 'C:\Projects\aftermarket-riie\data\sales_history.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

BULK INSERT dbo.returns
FROM 'C:\Projects\aftermarket-riie\data\returns.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);

BULK INSERT dbo.inventory_snapshot
FROM 'C:\Projects\aftermarket-riie\data\inventory_snapshot.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDTERMINATOR=',', ROWTERMINATOR='0x0a', TABLOCK);
GO

-------------------------------------------------------------------------
-- ROW-COUNT CHECK  (expected vs loaded)
-------------------------------------------------------------------------
SELECT 'location_master'    AS table_name, COUNT(*) AS rows_loaded, 51      AS expected FROM dbo.location_master
UNION ALL SELECT 'supplier_master',     COUNT(*), 45      FROM dbo.supplier_master
UNION ALL SELECT 'customer_master',     COUNT(*), 200     FROM dbo.customer_master
UNION ALL SELECT 'sku_master',          COUNT(*), 500     FROM dbo.sku_master
UNION ALL SELECT 'sales_history',       COUNT(*), 750000  FROM dbo.sales_history
UNION ALL SELECT 'returns',             COUNT(*), 37500   FROM dbo.returns
UNION ALL SELECT 'inventory_snapshot',  COUNT(*), 26000   FROM dbo.inventory_snapshot;
GO

-------------------------------------------------------------------------
-- FOREIGN KEYS  (added after load)
-------------------------------------------------------------------------
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

PRINT 'Load complete. 7 tables populated and foreign keys enforced.';
GO
