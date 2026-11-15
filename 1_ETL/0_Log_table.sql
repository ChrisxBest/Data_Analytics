-- Central Execution Log Table
IF OBJECT_ID('dbo.ETL_ExecutionLog', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.ETL_ExecutionLog (
            LogID              INT            IDENTITY (1, 1) PRIMARY KEY,
            ProcessName        VARCHAR (100)  NOT NULL,
            ExecutionStartTime DATETIME       NOT NULL,
            ExecutionEndTime   DATETIME       NULL,
            Status             VARCHAR (20)   NOT NULL, -- 'RUNNING', 'SUCCESS', 'FAILED'
            RowsAffected       INT            NULL,
            ErrorMessage       NVARCHAR (MAX) NULL
        );
    END


GO