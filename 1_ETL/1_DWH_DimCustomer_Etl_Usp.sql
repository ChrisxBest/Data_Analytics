-- ==========================================================
-- SCRIPT 1: DWH Infrastructure & SCD Type 2 Incremental ETL
-- ==========================================================
USE AdventureWorksDW2025;


GO
-- ----------------------------------------------------------
-- 1. Create Staging & Dim Tables (Idempotent)
-- ----------------------------------------------------------
-- Staging Table (Transient Raw Data Layer - Full Load)
IF OBJECT_ID('dbo.Staging_Customer', 'U') IS NOT NULL
    DROP TABLE dbo.Staging_Customer;


GO
CREATE TABLE dbo.Staging_Customer (
    CustomerID   INT           NOT NULL,
    FirstName    NVARCHAR (50) NULL,
    LastName     NVARCHAR (50) NULL,
    ModifiedDate DATETIME      NULL
);


GO
-- Target Dimension Table (Persistent DWH Layer - SCD Type 2)
IF OBJECT_ID('dbo.DimCustomer_Local', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.DimCustomer_Local (
            CustomerKey   INT            IDENTITY (1, 1) PRIMARY KEY,
            CustomerID    INT            NOT NULL, -- NOT UNIQUE anymore to allow history versions!
            FullName      NVARCHAR (101) NOT NULL,
            ModifiedDate  DATETIME       NULL,
            ValidFrom     DATETIME       NOT NULL, -- Start date of this version
            ValidTo       DATETIME       NULL, -- End date (NULL = currently active record)
            IsCurrent     BIT            NOT NULL, -- 1 = Active version, 0 = Historical version
            ETL_CreatedAt DATETIME       DEFAULT GETDATE()
        );
    END


GO
-- ----------------------------------------------------------
-- 2. Create or Update SCD Type 2 Stored Procedure
-- ----------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.usp_RunCustomerETL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @StartTime AS DATETIME = GETDATE();
    DECLARE @ProcessName AS VARCHAR (100) = 'Load_DimCustomer_SCD2';
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
        TRUNCATE TABLE dbo.Staging_Customer;
        INSERT INTO dbo.Staging_Customer (
            CustomerID,
            FirstName,
            LastName,
            ModifiedDate
        )
        SELECT c.CustomerID,
               p.FirstName,
               p.LastName,
               c.ModifiedDate
        FROM   AdventureWorks2025.Sales.Customer AS c
               INNER JOIN
               AdventureWorks2025.Person.Person AS p
               ON c.PersonID = p.BusinessEntityID
        WHERE  p.PersonType = 'IN' -- Only Individual Customers
               AND EXISTS (SELECT 1
                           FROM   AdventureWorks2025.Sales.SalesOrderHeader AS soh
                           WHERE  soh.CustomerID = c.CustomerID);
        -- 3. TRANSFORM & LOAD (SCD Type 2 Processing)
        BEGIN TRANSACTION;
        -- Step A: EXPIRE existing active records if attributes have changed
        UPDATE Target
        SET    Target.ValidTo   = @StartTime,
               Target.IsCurrent = 0
        FROM   dbo.DimCustomer_Local AS Target
               INNER JOIN
               (SELECT CustomerID,
                       LTRIM(RTRIM(ISNULL(FirstName, ''))) + ' ' + LTRIM(RTRIM(ISNULL(LastName, ''))) AS FullName,
                       ModifiedDate
                FROM   dbo.Staging_Customer
                WHERE  FirstName IS NOT NULL) AS Source
               ON Target.CustomerID = Source.CustomerID
        WHERE  Target.IsCurrent = 1
               AND (Target.FullName <> Source.FullName
                    OR ISNULL(Target.ModifiedDate, '1900-01-01') <> ISNULL(Source.ModifiedDate, '1900-01-01'));
        -- Step B: INSERT new records (Brand new customers + newly expired versions)
        INSERT INTO dbo.DimCustomer_Local (
            CustomerID,
            FullName,
            ModifiedDate,
            ValidFrom,
            ValidTo,
            IsCurrent,
            ETL_CreatedAt
        )
        SELECT Source.CustomerID,
               Source.FullName,
               Source.ModifiedDate,
               '1900-01-01' AS ValidFrom,
               NULL AS ValidTo,
               1 AS IsCurrent,
               GETDATE() AS ETL_CreatedAt
        FROM   (SELECT CustomerID,
                       LTRIM(RTRIM(ISNULL(FirstName, ''))) + ' ' + LTRIM(RTRIM(ISNULL(LastName, ''))) AS FullName,
                       ModifiedDate
                FROM   dbo.Staging_Customer
                WHERE  FirstName IS NOT NULL) AS Source
        WHERE  NOT EXISTS (SELECT 1
                           FROM   dbo.DimCustomer_Local AS Target
                           WHERE  Target.CustomerID = Source.CustomerID
                                  AND Target.IsCurrent = 1
                                  AND Target.FullName = Source.FullName
                                  AND ISNULL(Target.ModifiedDate, '1900-01-01') = ISNULL(Source.ModifiedDate, '1900-01-01'));
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
EXECUTE dbo.usp_RunCustomerETL ;

SELECT COUNT(*) AS TotalRows
FROM   dbo.DimCustomer_Local;

SELECT *
FROM   dbo.ETL_ExecutionLog;


-- Drop table dbo.DimCustomer_Local;
-- drop table dbo.ETL_ExecutionLog;