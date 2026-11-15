-- ==========================================================
-- SCRIPT: Enterprise ETL Job (Customer + Fact Sales)
-- ==========================================================
USE msdb;
GO

DECLARE @JobName      SYSNAME = N'Daily_Enterprise_Sales_ETL_Job';
DECLARE @ScheduleName SYSNAME = N'Daily_Schedule_01PM';

-- 1. Clean Up existing job
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC dbo.sp_delete_job @job_name = @JobName, @delete_unused_schedule = 1;
END

-- 2. Create Job
EXEC dbo.sp_add_job 
    @job_name     = @JobName,
    @enabled      = 1,
    @description  = N'Daily Enterprise ETL: 1. Customer SCD2, 2. Fact Internet Sales.';

-- 3. Add Step 1: Customer Dimension ETL
EXEC dbo.sp_add_jobstep 
    @job_name           = @JobName,
    @step_id            = 1,
    @step_name          = N'Step 1: Run Customer SCD2 ETL',
    @subsystem          = N'TSQL',
    @command            = N'EXEC dbo.usp_RunCustomerETL;',
    @database_name      = N'AdventureWorksDW2025',
    @on_success_action  = 3, -- 3 = On success, go to the NEXT step
    @on_fail_action     = 2; -- 2 = Quit with failure

-- 4. Add Step 2: Fact Internet Sales ETL
EXEC dbo.sp_add_jobstep 
    @job_name           = @JobName,
    @step_id            = 2,
    @step_name          = N'Step 2: Run Fact Internet Sales ETL',
    @subsystem          = N'TSQL',
    @command            = N'EXEC dbo.usp_RunFactInternetSalesETL;',
    @database_name      = N'AdventureWorksDW2025',
    @on_success_action  = 1, -- 1 = Quit with success
    @on_fail_action     = 2; -- 2 = Quit with failure

-- 5. Attach Schedule (Runs daily at 01:00 PM)
EXEC dbo.sp_add_jobschedule 
    @job_name           = @JobName,
    @name               = @ScheduleName,
    @enabled            = 1,
    @freq_type          = 4,      -- Daily
    @freq_interval      = 1,      -- Every 1 day
    @active_start_time  = 130000; -- 1:00:00 PM

-- 6. Assign Job to local server
EXEC dbo.sp_add_jobserver @job_name = @JobName;
GO

PRINT 'Enterprise Multi-Step ETL Job successfully deployed!';