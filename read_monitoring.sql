WITH EventData AS
(
    SELECT
        CONVERT(xml, event_data) AS EventXml
    FROM sys.fn_xe_file_target_read_file
    (
        N'E:\SQL_Diag\*.xel',
        NULL,
        NULL,
        NULL
    )
),
ParsedData AS
(
    SELECT
        EventXml.value(
            '(event/@timestamp)[1]',
            'datetime2'
        ) AS EventTimeUTC,

        EventXml.value(
            '(event/@name)[1]',
            'nvarchar(100)'
        ) AS EventName,

        EventXml.value(
            '(event/data[@name="duration"]/value)[1]',
            'bigint'
        ) AS DurationMicroseconds,

        EventXml.value(
            '(event/data[@name="cpu_time"]/value)[1]',
            'bigint'
        ) AS CpuMicroseconds,

        EventXml.value(
            '(event/data[@name="logical_reads"]/value)[1]',
            'bigint'
        ) AS LogicalReads,

        EventXml.value(
            '(event/data[@name="physical_reads"]/value)[1]',
            'bigint'
        ) AS PhysicalReads,

        EventXml.value(
            '(event/data[@name="writes"]/value)[1]',
            'bigint'
        ) AS Writes,

        EventXml.value(
            '(event/data[@name="row_count"]/value)[1]',
            'bigint'
        ) AS [RowCount],

        EventXml.value(
            '(event/action[@name="session_id"]/value)[1]',
            'int'
        ) AS SPID,

        EventXml.value(
            '(event/action[@name="database_name"]/value)[1]',
            'nvarchar(256)'
        ) AS DatabaseName,

        EventXml.value(
            '(event/action[@name="client_hostname"]/value)[1]',
            'nvarchar(256)'
        ) AS ClientHost,

        EventXml.value(
            '(event/action[@name="client_app_name"]/value)[1]',
            'nvarchar(256)'
        ) AS ClientApplication,

        EventXml.value(
            '(event/action[@name="username"]/value)[1]',
            'nvarchar(256)'
        ) AS SqlLogin,

        COALESCE
        (
            NULLIF
            (
                EventXml.value(
                    '(event/data[@name="statement"]/value)[1]',
                    'nvarchar(max)'
                ),
                N''
            ),
            NULLIF
            (
                EventXml.value(
                    '(event/data[@name="batch_text"]/value)[1]',
                    'nvarchar(max)'
                ),
                N''
            ),
            EventXml.value(
                '(event/action[@name="sql_text"]/value)[1]',
                'nvarchar(max)'
            )
        ) AS SqlText
    FROM EventData
)
SELECT
    DATEADD
    (
        MINUTE,
        DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()),
        EventTimeUTC
    ) AS EventTimeLocal,

    EventName,
    SPID,
    DatabaseName,
    ClientHost,
    ClientApplication,
    SqlLogin,

    CAST(DurationMicroseconds / 1000000.0 AS decimal(18,3))
        AS DurationSeconds,

    CAST(CpuMicroseconds / 1000000.0 AS decimal(18,3))
        AS CpuSeconds,

    LogicalReads,
    PhysicalReads,
    Writes,
    [RowCount],
    SqlText
FROM ParsedData
where 

DATEADD
    (
        MINUTE,
        DATEDIFF(MINUTE, GETUTCDATE(), GETDATE()),
        EventTimeUTC
    )
	>='2026-09-18'
ORDER BY EventTimeUTC DESC;
