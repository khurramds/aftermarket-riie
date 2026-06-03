/* =====================================================================
   Aftermarket RIIE  -  03_fix_location_region.sql
   Corrects location_master.region to match the generator's 6-region
   scheme (pulled from customer_master). In-place UPDATE — no reload,
   no FK changes needed, safe to re-run.
   ===================================================================== */

USE aftermarket_db;
GO

UPDATE dbo.location_master SET region = 'Midwest'
  WHERE state_code IN ('IA','IL','IN','MI','MN','MO','OH','WI');

UPDATE dbo.location_master SET region = 'Northeast'
  WHERE state_code IN ('CT','MA','ME','NY','PA','RI','VT','NH','NJ');

UPDATE dbo.location_master SET region = 'Plains'
  WHERE state_code IN ('KS','ND','NE','OK','SD');

UPDATE dbo.location_master SET region = 'Southeast'
  WHERE state_code IN ('AL','DE','FL','GA','KY','MD','MS','NC','SC','TN','VA','WV','DC');

UPDATE dbo.location_master SET region = 'Southwest'
  WHERE state_code IN ('AZ','CO','NM','NV','TX','UT');

UPDATE dbo.location_master SET region = 'West'
  WHERE state_code IN ('AR','CA','ID','LA','MT','OR','WA','WY','AK','HI');
GO

-- verify: location regions should now match customer_master regions
SELECT region, COUNT(*) AS states
FROM dbo.location_master
GROUP BY region
ORDER BY region;
GO

PRINT 'location_master.region corrected to match generator scheme.';
GO
