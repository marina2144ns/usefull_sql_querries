USE [master];
GO

DECLARE @DatabaseId int = DB_ID(N'trade_2020_uat');

IF @DatabaseId IS NULL
BEGIN
    RAISERROR(
        N'База trade_2020_uat не найдена. Сессия не создана.',
        16,
        1
    );
    RETURN;
END;

IF EXISTS
(
    SELECT 1
    FROM sys.server_event_sessions
    WHERE name = N'OneC_HeavyQueries'
)
BEGIN
    RAISERROR(
        N'Сессия OneC_HeavyQueries уже существует. Повторное создание отменено.',
        16,
        1
    );
    RETURN;
END;

DECLARE @CreateSession nvarchar(max);

SET @CreateSession = N'
CREATE EVENT SESSION [OneC_HeavyQueries]
ON SERVER

ADD EVENT sqlserver.rpc_completed
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.session_id,
        sqlserver.sql_text,
        sqlserver.username
    )
    WHERE
    (
        [sqlserver].[database_id] = ' +
        CONVERT(nvarchar(20), @DatabaseId) + N'
        AND
        (
            [duration] >= 300000000
            OR [logical_reads] >= 5000000
            OR [cpu_time] >= 60000000
        )
    )
),

ADD EVENT sqlserver.sql_batch_completed
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.session_id,
        sqlserver.sql_text,
        sqlserver.username
    )
    WHERE
    (
        [sqlserver].[database_id] = ' +
        CONVERT(nvarchar(20), @DatabaseId) + N'
        AND
        (
            [duration] >= 300000000
            OR [logical_reads] >= 5000000
            OR [cpu_time] >= 60000000
        )
    )
)

ADD TARGET package0.event_file
(
    SET
        filename = N''C:\Users\m.emelyanova\Documents\SQL_Diagnostics\OneC_HeavyQueries.xel'',
        max_file_size = 100,
        max_rollover_files = 10
)

WITH
(
    MAX_MEMORY = 4096 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 30 SECONDS,
    MAX_EVENT_SIZE = 0 KB,
    MEMORY_PARTITION_MODE = NONE,
    TRACK_CAUSALITY = OFF,
    STARTUP_STATE = ON
);';

EXEC sys.sp_executesql @CreateSession;

PRINT N'Сессия OneC_HeavyQueries создана.';
GO
