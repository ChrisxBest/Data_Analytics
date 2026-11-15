-- ==========================================================
-- SCRIPT 2: SQL Server Agent Job & Schedule Setup (Idempotent)
-- ==========================================================
USE msdb;
GO

DECLARE @JobName      SYSNAME = N'Daily_Customer_ETL_Job';
DECLARE @ScheduleName SYSNAME = N'Daily_Schedule_01PM';

-- ----------------------------------------------------------
-- 1. Clean Up: Remove existing job and linked schedules
-- ----------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @JobName)
BEGIN
    EXEC dbo.sp_delete_job 
        @job_name = @JobName, 
        @delete_unused_schedule = 1;
END

-- ----------------------------------------------------------
-- 2. Create Job, Step, Schedule & Server Binding
-- ----------------------------------------------------------
-- Create the Job
EXEC dbo.sp_add_job 
    @job_name     = @JobName,
    @enabled      = 1,
    @description  = N'Automated daily SCD Type 2 ETL process for DimCustomer_Local.';

-- Add Job Step (Calls the Stored Procedure)
EXEC dbo.sp_add_jobstep 
    @job_name          = @JobName,
    @step_name         = N'Execute usp_RunCustomerETL',
    @subsystem         = N'TSQL',
    @command           = N'EXEC dbo.usp_RunCustomerETL;',
    @database_name     = N'AdventureWorksDW2025',
    @on_success_action = 1, 
    @on_fail_action    = 2; 

-- Attach Schedule (Runs daily at 01:00:00 PM)
EXEC dbo.sp_add_jobschedule 
    @job_name            = @JobName,
    @name                = @ScheduleName,
    @enabled             = 1,
    @freq_type           = 4,      -- Daily
    @freq_interval       = 1,      -- Every 1 day
    @active_start_time   = 132600; -- 1:26:00 PM

-- Assign Job to the local server instance
EXEC dbo.sp_add_jobserver 
    @job_name = @JobName;
GO

PRINT 'SQL Server Agent Job and Nightly Schedule successfully deployed!';

-- Select  * from msdb.dbo.sysjobs