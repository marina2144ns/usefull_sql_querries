SET NOCOUNT ON;

DECLARE @SchemaName sysname;
DECLARE @TableName  sysname;
DECLARE @ObjectId   int;
DECLARE @SQL        nvarchar(max);

DECLARE table_cursor CURSOR LOCAL FAST_FORWARD FOR
SELECT
    s.name,
    t.name,
    t.object_id
FROM sys.tables t
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY
    s.name,
    t.name;

OPEN table_cursor;

FETCH NEXT FROM table_cursor
INTO @SchemaName, @TableName, @ObjectId;

WHILE @@FETCH_STATUS = 0
BEGIN

    PRINT '------------------------------------------------------------';
    PRINT '-- TABLE: [' + @SchemaName + '].[' + @TableName + ']';
    PRINT '------------------------------------------------------------';
    PRINT '';

    SET @SQL =
        'CREATE TABLE [' + @SchemaName + '].[' + @TableName + '] (' + CHAR(13) + CHAR(10);

    ----------------------------------------------------------------
    -- COLUMNS
    ----------------------------------------------------------------
    SELECT
        @SQL = @SQL +
        '    [' + c.name + '] ' +

        CASE
            WHEN ty.is_user_defined = 1
                THEN '[' + SCHEMA_NAME(ty.schema_id) + '].[' + ty.name + ']'
            ELSE '[' + ty.name + ']'
        END +

        CASE
            WHEN ty.name IN ('varchar', 'char', 'varbinary', 'binary')
                THEN
                    CASE
                        WHEN c.max_length = -1 THEN '(MAX)'
                        ELSE '(' + CAST(c.max_length AS varchar(10)) + ')'
                    END

            WHEN ty.name IN ('nvarchar', 'nchar')
                THEN
                    CASE
                        WHEN c.max_length = -1 THEN '(MAX)'
                        ELSE '(' + CAST(c.max_length / 2 AS varchar(10)) + ')'
                    END

            WHEN ty.name IN ('decimal', 'numeric')
                THEN '('
                    + CAST(c.precision AS varchar(10))
                    + ','
                    + CAST(c.scale AS varchar(10))
                    + ')'

            WHEN ty.name IN ('datetime2', 'datetimeoffset', 'time')
                THEN '(' + CAST(c.scale AS varchar(10)) + ')'

            ELSE ''
        END +

        CASE
            WHEN c.is_identity = 1
                THEN
                    ' IDENTITY('
                    + CAST(ic.seed_value AS varchar(50))
                    + ','
                    + CAST(ic.increment_value AS varchar(50))
                    + ')'
            ELSE ''
        END +

        CASE
            WHEN c.collation_name IS NOT NULL
             AND ty.name IN ('varchar', 'char', 'nvarchar', 'nchar', 'text', 'ntext')
                THEN ' COLLATE ' + c.collation_name
            ELSE ''
        END +

        CASE
            WHEN dc.definition IS NOT NULL
                THEN ' DEFAULT ' + dc.definition
            ELSE ''
        END +

        CASE
            WHEN c.is_nullable = 1
                THEN ' NULL'
            ELSE ' NOT NULL'
        END +

        CASE
            WHEN c.column_id <
            (
                SELECT MAX(c2.column_id)
                FROM sys.columns c2
                WHERE c2.object_id = c.object_id
            )
                THEN ','
            ELSE ''
        END +

        CHAR(13) + CHAR(10)

    FROM sys.columns c

    JOIN sys.types ty
        ON c.user_type_id = ty.user_type_id

    LEFT JOIN sys.identity_columns ic
        ON ic.object_id = c.object_id
       AND ic.column_id = c.column_id

    LEFT JOIN sys.default_constraints dc
        ON dc.parent_object_id = c.object_id
       AND dc.parent_column_id = c.column_id

    WHERE c.object_id = @ObjectId

    ORDER BY c.column_id;

    SET @SQL = @SQL + ');';

    PRINT @SQL;
    PRINT '';
    PRINT 'GO';
    PRINT '';

    ----------------------------------------------------------------
    -- PRIMARY KEY / UNIQUE CONSTRAINTS
    ----------------------------------------------------------------
    DECLARE
        @IndexId       int,
        @IndexName     sysname,
        @IndexType     varchar(20),
        @IsPrimaryKey  bit,
        @IsUniqueConst bit,
        @Columns       nvarchar(max);

    DECLARE constraint_cursor CURSOR LOCAL FAST_FORWARD FOR

    SELECT
        i.index_id,
        i.name,
        CASE
            WHEN i.type = 1 THEN 'CLUSTERED'
            ELSE 'NONCLUSTERED'
        END,
        i.is_primary_key,
        i.is_unique_constraint
    FROM sys.indexes i
    WHERE i.object_id = @ObjectId
      AND
      (
          i.is_primary_key = 1
          OR i.is_unique_constraint = 1
      )
    ORDER BY i.index_id;

    OPEN constraint_cursor;

    FETCH NEXT FROM constraint_cursor
    INTO
        @IndexId,
        @IndexName,
        @IndexType,
        @IsPrimaryKey,
        @IsUniqueConst;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        SET @Columns = '';

        SELECT
            @Columns =
                @Columns
                + CASE
                    WHEN LEN(@Columns) > 0 THEN ', '
                    ELSE ''
                  END
                + '[' + c.name + '] '
                + CASE
                    WHEN ic.is_descending_key = 1
                        THEN 'DESC'
                    ELSE 'ASC'
                  END

        FROM sys.index_columns ic

        JOIN sys.columns c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id

        WHERE ic.object_id = @ObjectId
          AND ic.index_id = @IndexId
          AND ic.is_included_column = 0
          AND ic.key_ordinal > 0

        ORDER BY ic.key_ordinal;

        SET @SQL =
            'ALTER TABLE [' + @SchemaName + '].[' + @TableName + '] ADD CONSTRAINT '
            + '[' + @IndexName + '] '
            +
            CASE
                WHEN @IsPrimaryKey = 1
                    THEN 'PRIMARY KEY '
                ELSE 'UNIQUE '
            END
            + @IndexType
            + ' ('
            + @Columns
            + ');';

        PRINT @SQL;
        PRINT 'GO';
        PRINT '';

        FETCH NEXT FROM constraint_cursor
        INTO
            @IndexId,
            @IndexName,
            @IndexType,
            @IsPrimaryKey,
            @IsUniqueConst;
    END

    CLOSE constraint_cursor;
    DEALLOCATE constraint_cursor;

    ----------------------------------------------------------------
    -- NORMAL INDEXES
    ----------------------------------------------------------------

    DECLARE
        @IsUnique       bit,
        @Filter         nvarchar(max),
        @FillFactor     tinyint,
        @IncludeColumns nvarchar(max),
        @Options        nvarchar(max);

    DECLARE index_cursor CURSOR LOCAL FAST_FORWARD FOR

    SELECT
        i.index_id,
        i.name,
        CASE
            WHEN i.type = 1 THEN 'CLUSTERED'
            WHEN i.type = 2 THEN 'NONCLUSTERED'
            ELSE ''
        END,
        i.is_unique,
        i.filter_definition,
        i.fill_factor

    FROM sys.indexes i

    WHERE i.object_id = @ObjectId
      AND i.index_id > 0
      AND i.type IN (1, 2)
      AND i.is_primary_key = 0
      AND i.is_unique_constraint = 0
      AND i.name IS NOT NULL

    ORDER BY i.index_id;

    OPEN index_cursor;

    FETCH NEXT FROM index_cursor
    INTO
        @IndexId,
        @IndexName,
        @IndexType,
        @IsUnique,
        @Filter,
        @FillFactor;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        SET @Columns = '';
        SET @IncludeColumns = '';
        SET @Options = '';

        ------------------------------------------------------------
        -- INDEX KEY COLUMNS
        ------------------------------------------------------------

        SELECT
            @Columns =
                @Columns
                + CASE
                    WHEN LEN(@Columns) > 0 THEN ', '
                    ELSE ''
                  END
                + '[' + c.name + '] '
                + CASE
                    WHEN ic.is_descending_key = 1
                        THEN 'DESC'
                    ELSE 'ASC'
                  END

        FROM sys.index_columns ic

        JOIN sys.columns c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id

        WHERE ic.object_id = @ObjectId
          AND ic.index_id = @IndexId
          AND ic.is_included_column = 0
          AND ic.key_ordinal > 0

        ORDER BY ic.key_ordinal;

        ------------------------------------------------------------
        -- INCLUDE COLUMNS
        ------------------------------------------------------------

        SELECT
            @IncludeColumns =
                @IncludeColumns
                + CASE
                    WHEN LEN(@IncludeColumns) > 0 THEN ', '
                    ELSE ''
                  END
                + '[' + c.name + ']'

        FROM sys.index_columns ic

        JOIN sys.columns c
            ON c.object_id = ic.object_id
           AND c.column_id = ic.column_id

        WHERE ic.object_id = @ObjectId
          AND ic.index_id = @IndexId
          AND ic.is_included_column = 1

        ORDER BY ic.index_column_id;

        ------------------------------------------------------------
        -- OPTIONS
        ------------------------------------------------------------

        IF ISNULL(@FillFactor, 0) <> 0
        BEGIN
            SET @Options =
                'WITH (FILLFACTOR = '
                + CAST(@FillFactor AS varchar(10))
                + ')';
        END

        ------------------------------------------------------------
        -- CREATE INDEX
        ------------------------------------------------------------

        SET @SQL =
            'CREATE '
            + CASE
                WHEN @IsUnique = 1 THEN 'UNIQUE '
                ELSE ''
              END
            + @IndexType
            + ' INDEX [' + @IndexName + ']'
            + ' ON [' + @SchemaName + '].[' + @TableName + ']'
            + ' ('
            + @Columns
            + ')';

        IF LEN(@IncludeColumns) > 0
        BEGIN
            SET @SQL =
                @SQL
                + ' INCLUDE ('
                + @IncludeColumns
                + ')';
        END

        IF @Filter IS NOT NULL
        BEGIN
            SET @SQL =
                @SQL
                + ' WHERE '
                + @Filter;
        END

        IF LEN(@Options) > 0
        BEGIN
            SET @SQL =
                @SQL
                + ' '
                + @Options;
        END

        SET @SQL = @SQL + ';';

        PRINT @SQL;
        PRINT 'GO';
        PRINT '';

        FETCH NEXT FROM index_cursor
        INTO
            @IndexId,
            @IndexName,
            @IndexType,
            @IsUnique,
            @Filter,
            @FillFactor;
    END

    CLOSE index_cursor;
    DEALLOCATE index_cursor;

    FETCH NEXT FROM table_cursor
    INTO @SchemaName, @TableName, @ObjectId;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;
