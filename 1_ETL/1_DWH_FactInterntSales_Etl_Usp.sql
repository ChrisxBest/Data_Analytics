-- ==========================================================
-- SCRIPT: Full FactInternetSales Enterprise ETL Pipeline (Fixed Columns)
-- ==========================================================
USE AdventureWorksDW2025;


GO
-- ----------------------------------------------------------
-- 1. Create Staging & Fact Tables (Idempotent)
-- ----------------------------------------------------------
IF OBJECT_ID('dbo.Staging_InternetSales', 'U') IS NOT NULL
    DROP TABLE dbo.Staging_InternetSales;


GO
CREATE TABLE dbo.Staging_InternetSales (
    SalesOrderID          INT           NOT NULL,
    SalesOrderDetailID    INT           NOT NULL,
    CustomerID            INT           NOT NULL,
    ProductID             INT           NOT NULL,
    SpecialOfferID        INT           NOT NULL,
    TerritoryID           INT           NOT NULL,
    CurrencyRateID        INT           NULL,
    SalesOrderNumber      NVARCHAR (25) NOT NULL,
    RevisionNumber        TINYINT       NOT NULL,
    OrderQty              SMALLINT      NOT NULL,
    UnitPrice             MONEY         NOT NULL,
    UnitPriceDiscount     MONEY         NOT NULL,
    LineTotal             MONEY         NOT NULL,
    StandardCost          MONEY         NULL,
    TaxAmt                MONEY         NOT NULL,
    Freight               MONEY         NOT NULL,
    CarrierTrackingNumber NVARCHAR (25) NULL,
    CustomerPONumber      NVARCHAR (25) NULL,
    OrderDate             DATETIME      NOT NULL,
    DueDate               DATETIME      NOT NULL,
    ShipDate              DATETIME      NOT NULL
);


GO
IF OBJECT_ID('dbo.FactInternetSales_Local', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.FactInternetSales_Local (
            SalesSaleKey          INT           IDENTITY (1, 1) PRIMARY KEY,
            ProductKey            INT           NULL,
            OrderDateKey          INT           NOT NULL,
            DueDateKey            INT           NOT NULL,
            ShipDateKey           INT           NOT NULL,
            CustomerKey           INT           NOT NULL,
            PromotionKey          INT           NOT NULL,
            CurrencyKey           INT           NOT NULL,
            SalesTerritoryKey     INT           NOT NULL,
            SalesOrderNumber      NVARCHAR (25) NOT NULL,
            SalesOrderLineNumber  INT           NOT NULL, -- In DWH behalten wir den Standardnamen für das Schema bei
            RevisionNumber        TINYINT       NOT NULL,
            OrderQuantity         SMALLINT      NOT NULL,
            UnitPrice             MONEY         NOT NULL,
            ExtendedAmount        MONEY         NOT NULL,
            UnitPriceDiscountPct  FLOAT         NOT NULL,
            DiscountAmount        MONEY         NOT NULL,
            ProductStandardCost   MONEY         NOT NULL,
            TotalProductCost      MONEY         NOT NULL,
            SalesAmount           MONEY         NOT NULL,
            TaxAmt                MONEY         NOT NULL,
            Freight               MONEY         NOT NULL,
            CarrierTrackingNumber NVARCHAR (25) NULL,
            CustomerPONumber      NVARCHAR (25) NULL,
            OrderDate             DATETIME      NOT NULL,
            DueDate               DATETIME      NOT NULL,
            ShipDate              DATETIME      NOT NULL,
            ETL_CreatedAt         DATETIME      DEFAULT GETDATE()
        );
    END


GO
-- ----------------------------------------------------------
-- 2. Create Stored Procedure for the Full Fact ETL Load
-- ----------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_RunFactInternetSalesETL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @StartTime AS DATETIME = GETDATE();
    DECLARE @ProcessName AS VARCHAR (100) = 'Load_FactInternetSales_Full';
    DECLARE @RowsAffected AS INT = 0;
    DECLARE @LogID AS INT;
    -- 1. Log Process Start
    INSERT  INTO dbo.ETL_ExecutionLog (
        ProcessName,
        ExecutionStartTime,
        Status
    )
    VALUES                            (@ProcessName, @StartTime, 'RUNNING');
    SET @LogID = SCOPE_IDENTITY();
    BEGIN TRY
        -- 2. EXTRACT: Full Load into Staging
        TRUNCATE TABLE dbo.Staging_InternetSales;
        INSERT INTO dbo.Staging_InternetSales (
            SalesOrderID,
            SalesOrderDetailID,
            CustomerID,
            ProductID,
            SpecialOfferID,
            TerritoryID,
            CurrencyRateID,
            SalesOrderNumber,
            RevisionNumber,
            OrderQty,
            UnitPrice,
            UnitPriceDiscount,
            LineTotal,
            StandardCost,
            TaxAmt,
            Freight,
            CarrierTrackingNumber,
            CustomerPONumber,
            OrderDate,
            DueDate,
            ShipDate
        )
        SELECT oh.SalesOrderID,
               od.SalesOrderDetailID, -- Korrekt aus der OLTP-Tabelle übernommen
               oh.CustomerID,
               od.ProductID,
               od.SpecialOfferID,
               oh.TerritoryID,
               oh.CurrencyRateID,
               oh.SalesOrderNumber,
               oh.RevisionNumber,
               od.OrderQty,
               od.UnitPrice,
               od.UnitPriceDiscount,
               od.LineTotal,
               pr.StandardCost,
               oh.TaxAmt,
               oh.Freight,
               od.CarrierTrackingNumber,
               oh.PurchaseOrderNumber,
               oh.OrderDate,
               oh.DueDate,
               oh.ShipDate
        FROM   AdventureWorks2025.Sales.SalesOrderHeader AS oh
               INNER JOIN
               AdventureWorks2025.Sales.SalesOrderDetail AS od
               ON oh.SalesOrderID = od.SalesOrderID
               INNER JOIN
               AdventureWorks2025.Sales.Customer AS c
               ON oh.CustomerID = c.CustomerID
               INNER JOIN
               AdventureWorks2025.Person.Person AS p
               ON c.PersonID = p.BusinessEntityID
               LEFT OUTER JOIN
               AdventureWorks2025.Production.Product AS pr
               ON od.ProductID = pr.ProductID
        WHERE  oh.OnlineOrderFlag = 1
               AND p.PersonType = 'IN';
        -- 3. TRANSFORM & LOAD
        BEGIN TRANSACTION;
        INSERT INTO dbo.FactInternetSales_Local (
            ProductKey,
            OrderDateKey,
            DueDateKey,
            ShipDateKey,
            CustomerKey,
            PromotionKey,
            CurrencyKey,
            SalesTerritoryKey,
            SalesOrderNumber,
            SalesOrderLineNumber,
            RevisionNumber,
            OrderQuantity,
            UnitPrice,
            ExtendedAmount,
            UnitPriceDiscountPct,
            DiscountAmount,
            ProductStandardCost,
            TotalProductCost,
            SalesAmount,
            TaxAmt,
            Freight,
            CarrierTrackingNumber,
            CustomerPONumber,
            OrderDate,
            DueDate,
            ShipDate
        )
        SELECT NULL AS ProductKey,
               CAST (FORMAT(stg.OrderDate, 'yyyyMMdd') AS INT) AS OrderDateKey,
               CAST (FORMAT(stg.DueDate, 'yyyyMMdd') AS INT) AS DueDateKey,
               CAST (FORMAT(stg.ShipDate, 'yyyyMMdd') AS INT) AS ShipDateKey,
               dc.CustomerKey,
               ISNULL(stg.SpecialOfferID, 1) AS PromotionKey,
               ISNULL(stg.CurrencyRateID, 1) AS CurrencyKey,
               ISNULL(stg.TerritoryID, 1) AS SalesTerritoryKey,
               stg.SalesOrderNumber,
               stg.SalesOrderDetailID AS SalesOrderLineNumber, -- Mappt die ID auf die Zeilennummer im DWH
               stg.RevisionNumber,
               stg.OrderQty AS OrderQuantity,
               stg.UnitPrice,
               (stg.UnitPrice * stg.OrderQty) AS ExtendedAmount,
               CAST (stg.UnitPriceDiscount AS FLOAT) AS UnitPriceDiscountPct,
               (stg.UnitPrice * stg.UnitPriceDiscount * stg.OrderQty) AS DiscountAmount,
               ISNULL(stg.StandardCost, 0) AS ProductStandardCost,
               (ISNULL(stg.StandardCost, 0) * stg.OrderQty) AS TotalProductCost,
               stg.LineTotal AS SalesAmount,
               stg.TaxAmt,
               stg.Freight,
               stg.CarrierTrackingNumber,
               stg.CustomerPONumber,
               stg.OrderDate,
               stg.DueDate,
               stg.ShipDate
        FROM   dbo.Staging_InternetSales AS stg
               INNER JOIN
               dbo.DimCustomer_Local AS dc
               ON stg.CustomerID = dc.CustomerID
                  AND stg.OrderDate >= dc.ValidFrom
                  AND (stg.OrderDate < dc.ValidTo
                       OR dc.ValidTo IS NULL);
        SET @RowsAffected = @@ROWCOUNT;
        COMMIT TRANSACTION;
        -- 4. Log Process Success
        UPDATE dbo.ETL_ExecutionLog
        SET    ExecutionEndTime = GETDATE(),
               Status           = 'SUCCESS',
               RowsAffected     = @RowsAffected
        WHERE  LogID = @LogID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK;
        DECLARE @DetailedError AS NVARCHAR (MAX) = CONCAT('ETL Error in Procedure [', ISNULL(ERROR_PROCEDURE(), @ProcessName), '] ', 'at Line ', CAST (ERROR_LINE() AS VARCHAR (10)), '. ', 'Error Number: ', CAST (ERROR_NUMBER() AS VARCHAR (10)), ' ', '(Severity: ', CAST (ERROR_SEVERITY() AS VARCHAR (10)), '). ', 'Details: ', ERROR_MESSAGE());
        UPDATE dbo.ETL_ExecutionLog
        SET    ExecutionEndTime = GETDATE(),
               Status           = 'FAILED',
               ErrorMessage     = @DetailedError
        WHERE  LogID = @LogID;
        THROW;
    END CATCH
END


GO
-- ==========================================================
-- 3. Execution & Verification
-- ==========================================================
EXECUTE dbo.usp_RunFactInternetSalesETL ;

SELECT COUNT(*) AS TotalRows
FROM   dbo.FactInternetSales_Local;

SELECT *
FROM   dbo.ETL_ExecutionLog;

-- Drop table dbo.FactInternetSales_Local;
-- drop table dbo.ETL_ExecutionLog;