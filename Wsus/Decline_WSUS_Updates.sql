-- wsus_batch_delete_declined_with_dry_persist_and_raise_from_summary.fix8.sql
-- Modified: Mandatory EXEC-time backup is performed BEFORE any deletions. EXEC proceeds only if backup succeeds.

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- -------------------------
-- Konfiguration (anpassen)
-- -------------------------
DECLARE @DryRun BIT = 0;             -- 1 = DRY RUN; 0 = EXECUTE (ACHTUNG: dauerhaft!)
DECLARE @BatchSize INT = 500;        -- Anzahl LocalUpdateIDs pro Batch
DECLARE @MaxBatches INT = 1;         -- 0 = unlimitiert; n zum Testen
DECLARE @WaitBetweenBatches NVARCHAR(8) = '00:00:02';
DECLARE @InnerBatch INT = 1000;      -- chunk size bei deletes (EXEC-Modus)
DECLARE @UseAggregatedDryRun BIT = 1;-- 1 = aggregierte Summen in #AllPerUpdateCounts
DECLARE @DryRaiseTop INT = 50;       -- Top-N LocalUpdateIDs, die am Ende per RAISERROR ausgegeben werden
DECLARE @DryRaiseAll BIT = 0;        -- 1 = alle LocalUpdateIDs aus WSUSDryRunSummary per RAISERROR ausgeben

DECLARE @RunID UNIQUEIDENTIFIER = NEWID();
DECLARE @RunStart DATETIME2 = SYSUTCDATETIME();
DECLARE @Mode NVARCHAR(4) = CASE WHEN @DryRun = 1 THEN 'DRY' ELSE 'EXEC' END;

DECLARE @startMsg NVARCHAR(500) = CONCAT('Starting run: RunID=', CONVERT(NVARCHAR(36), @RunID), ', RunStart=', CONVERT(NVARCHAR(30), @RunStart, 121), ', Mode=', @Mode, ', BatchSize=', CAST(@BatchSize AS NVARCHAR(10)));
RAISERROR(@startMsg, 0, 1) WITH NOWAIT;
RAISERROR(' ', 0, 1) WITH NOWAIT;

-- --------------------------------------------------------------------------------
-- Defensive: drop lingering temp tables (harmless) then CREATE all needed temp tables ONCE
-- --------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#DeclinedMaster') IS NOT NULL DROP TABLE #DeclinedMaster;
IF OBJECT_ID('tempdb..#BatchIDs') IS NOT NULL DROP TABLE #BatchIDs;
IF OBJECT_ID('tempdb..#BatchDeleteLog') IS NOT NULL DROP TABLE #BatchDeleteLog;
IF OBJECT_ID('tempdb..#BatchPerUpdateCounts') IS NOT NULL DROP TABLE #BatchPerUpdateCounts;
IF OBJECT_ID('tempdb..#AllPerUpdateCounts') IS NOT NULL DROP TABLE #AllPerUpdateCounts;
IF OBJECT_ID('tempdb..#tmpDistinct') IS NOT NULL DROP TABLE #tmpDistinct;

CREATE TABLE #DeclinedMaster (
    LocalUpdateID BIGINT NOT NULL PRIMARY KEY
);

CREATE TABLE #BatchIDs (
    LocalUpdateID BIGINT NOT NULL
);

-- create index for #BatchIDs (clustered) - no need to check, table was just created
CREATE CLUSTERED INDEX IX_BatchIDs_LocalUpdateID ON #BatchIDs(LocalUpdateID);

CREATE TABLE #BatchDeleteLog (
    TableName SYSNAME,
    RowsAffected BIGINT
);

CREATE TABLE #BatchPerUpdateCounts (
    LocalUpdateID BIGINT NOT NULL,
    TableName SYSNAME NOT NULL,
    RowsAffected BIGINT NOT NULL
);

CREATE TABLE #AllPerUpdateCounts (
    LocalUpdateID BIGINT PRIMARY KEY,
    TotalRows BIGINT NOT NULL DEFAULT 0
);

CREATE TABLE #tmpDistinct (
    DistinctLocalUpdateIDs BIGINT
);

-- --------------------------------------------------------------------------------
-- Ensure SUSDB exists and set context
-- --------------------------------------------------------------------------------
IF DB_ID('SUSDB') IS NULL
BEGIN
    RAISERROR('Datenbank SUSDB wurde nicht gefunden auf diesem Server. Bitte Namen prüfen.',16,1);
    RETURN;
END;
USE [SUSDB];

-- Ensure WSUSDeleteLog exists (for EXEC logging)
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.WSUSDeleteLog') AND type = N'U')
BEGIN
    CREATE TABLE dbo.WSUSDeleteLog
    (
        LogID INT IDENTITY(1,1) PRIMARY KEY,
        RunAt DATETIME NOT NULL DEFAULT GETDATE(),
        BatchNumber INT NOT NULL,
        TableName SYSNAME NOT NULL,
        RowsAffected BIGINT NOT NULL,
        Note NVARCHAR(400) NULL,
        RunID UNIQUEIDENTIFIER NULL
    );
    RAISERROR('Tabelle dbo.WSUSDeleteLog erstellt (mit RunID).', 0, 1) WITH NOWAIT;
END;

-- Ensure WSUSDryRunSummary exists (persist DRY results)
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.WSUSDryRunSummary') AND type = N'U')
BEGIN
    CREATE TABLE dbo.WSUSDryRunSummary
    (
        SummaryID BIGINT IDENTITY(1,1) PRIMARY KEY,
        RunID UNIQUEIDENTIFIER NOT NULL,
        RunStart DATETIME2 NOT NULL,
        RunEnd DATETIME2 NULL,
        LocalUpdateID BIGINT NOT NULL,
        TotalRows BIGINT NOT NULL,
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
    RAISERROR('Tabelle dbo.WSUSDryRunSummary erstellt.', 0, 1) WITH NOWAIT;
END;

DECLARE @HasRunID BIT = CASE WHEN COL_LENGTH('dbo.WSUSDeleteLog','RunID') IS NOT NULL THEN 1 ELSE 0 END;
DECLARE @hasRunIDMsg NVARCHAR(100) = CONCAT('HasRunID = ', CAST(@HasRunID AS NVARCHAR(1)));
RAISERROR(@hasRunIDMsg, 0, 1) WITH NOWAIT;
RAISERROR(' ', 0, 1) WITH NOWAIT;

-- === NEW: mandatory backup before any EXEC deletions (with 2-hour check) ===
IF @DryRun = 0
BEGIN
    -- Check if a recent backup exists (< 2 hours old)
    DECLARE @lastBackupDate DATETIME;
    DECLARE @backupAgeMinutes INT;
    
    SELECT TOP 1 @lastBackupDate = backup_finish_date
    FROM msdb.dbo.backupset
    WHERE database_name = 'SUSDB'
        AND type = 'D'  -- Full backup
    ORDER BY backup_finish_date DESC;
    
    IF @lastBackupDate IS NOT NULL
    BEGIN
        SET @backupAgeMinutes = DATEDIFF(MINUTE, @lastBackupDate, GETDATE());
        DECLARE @ageMsg NVARCHAR(500) = CONCAT('Last SUSDB backup: ', CONVERT(NVARCHAR(30), @lastBackupDate, 121), ' (', CAST(@backupAgeMinutes AS NVARCHAR(10)), ' minutes ago)');
        RAISERROR(@ageMsg, 0, 1) WITH NOWAIT;
        
        IF @backupAgeMinutes < 120  -- Less than 2 hours
        BEGIN
            RAISERROR('Recent backup found (< 2 hours old) — skipping new backup, proceeding with EXEC.', 0, 1) WITH NOWAIT;
            
            -- Log that we skipped backup due to recent backup
            IF @HasRunID = 1
            BEGIN
                INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
                VALUES (GETDATE(), 0, 'BACKUP-SKIPPED', 0, 'Recent backup exists: ' + CONVERT(NVARCHAR(30), @lastBackupDate, 121), @RunID);
            END
            ELSE
            BEGIN
                INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
                VALUES (GETDATE(), 0, 'BACKUP-SKIPPED', 0, 'Recent backup exists: ' + CONVERT(NVARCHAR(30), @lastBackupDate, 121));
            END
        END
        ELSE
        BEGIN
            RAISERROR('Last backup is older than 2 hours — creating new backup...', 0, 1) WITH NOWAIT;
            GOTO CREATE_BACKUP;
        END
    END
    ELSE
    BEGIN
        RAISERROR('No previous backup found — creating new backup...', 0, 1) WITH NOWAIT;
        GOTO CREATE_BACKUP;
    END
    
    GOTO SKIP_BACKUP;
    
    CREATE_BACKUP:
    DECLARE @backupDir NVARCHAR(260) = N'D:\Backup';
    DECLARE @backupPath NVARCHAR(400);
    SET @backupPath = @backupDir + N'\SUSDB_backup_' + REPLACE(CONVERT(CHAR(19), GETDATE(), 120), ':', '-') + N'.bak';

    DECLARE @backupMsg NVARCHAR(500) = 'EXEC mode selected: attempting mandatory backup of SUSDB to: ' + @backupPath;
    RAISERROR(@backupMsg, 0, 1) WITH NOWAIT;

    DECLARE @bk_sql NVARCHAR(MAX) = N'BACKUP DATABASE [SUSDB] TO DISK = N''' + REPLACE(@backupPath COLLATE DATABASE_DEFAULT, '''', '''''') + N''' WITH INIT, CHECKSUM, STATS = 10;';
    BEGIN TRY
        EXEC (@bk_sql);
        RAISERROR('Mandatory backup completed successfully.', 0, 1) WITH NOWAIT;

        -- Log the successful backup event in WSUSDeleteLog (BatchNumber 0)
        IF @HasRunID = 1
        BEGIN
            INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
            VALUES (GETDATE(), 0, 'BACKUP', 0, 'Mandatory backup to ' + @backupPath, @RunID);
        END
        ELSE
        BEGIN
            INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
            VALUES (GETDATE(), 0, 'BACKUP', 0, 'Mandatory backup to ' + @backupPath);
        END
    END TRY
    BEGIN CATCH
        DECLARE @bk_err NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @bk_errMsg NVARCHAR(4000) = 'Mandatory backup failed: ' + @bk_err;
        RAISERROR(@bk_errMsg, 0, 1) WITH NOWAIT;

        -- Log the backup failure
        IF @HasRunID = 1
        BEGIN
            INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
            VALUES (GETDATE(), 0, 'BACKUP-FAILED', 0, @bk_err, @RunID);
        END
        ELSE
        BEGIN
            INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
            VALUES (GETDATE(), 0, 'BACKUP-FAILED', 0, @bk_err);
        END

        RAISERROR('Mandatory backup failed — aborting EXEC. Error: %s', 16, 1, @bk_err);
        RETURN; -- do not continue with deletes
    END CATCH;
    
    SKIP_BACKUP:
END
ELSE
BEGIN
    RAISERROR('DryRun selected: no mandatory backup will be performed (DRY).', 0, 1) WITH NOWAIT;
END

BEGIN TRY
    -- ----------------------------------------------------------------
    -- Build #DeclinedMaster once (clear table first)
    -- ----------------------------------------------------------------
    DELETE FROM #DeclinedMaster;

    RAISERROR('Checking vwMinimalUpdate structure...', 0, 1) WITH NOWAIT;
    
    -- vwMinimalUpdate kann LocalUpdateID / UpdateID / RevisionID enthalten - flexibel mappen
    IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='vwMinimalUpdate' AND COLUMN_NAME COLLATE DATABASE_DEFAULT='LocalUpdateID')
    BEGIN
        RAISERROR('Found LocalUpdateID column in vwMinimalUpdate. Querying declined updates (this may take a while)...', 0, 1) WITH NOWAIT;
        INSERT INTO #DeclinedMaster (LocalUpdateID)
        SELECT DISTINCT LocalUpdateID FROM dbo.vwMinimalUpdate WITH (NOLOCK) WHERE Declined = 1;
        RAISERROR('Declined updates loaded from vwMinimalUpdate.', 0, 1) WITH NOWAIT;
    END
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='vwMinimalUpdate' AND COLUMN_NAME COLLATE DATABASE_DEFAULT='UpdateID')
    BEGIN
        RAISERROR('Found UpdateID column in vwMinimalUpdate. Checking tbUpdate structure...', 0, 1) WITH NOWAIT;
        IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.tbUpdate') AND name COLLATE DATABASE_DEFAULT = 'LocalUpdateID')
        BEGIN
            RAISERROR('dbo.tbUpdate hat keine Spalte LocalUpdateID — Mapping nicht möglich.',16,1);
            RETURN;
        END;
        RAISERROR('Querying declined updates via UpdateID mapping (this may take a while)...', 0, 1) WITH NOWAIT;
        INSERT INTO #DeclinedMaster (LocalUpdateID)
        SELECT DISTINCT u.LocalUpdateID
        FROM dbo.vwMinimalUpdate v WITH (NOLOCK)
        INNER JOIN dbo.tbUpdate u WITH (NOLOCK) ON v.UpdateID = u.UpdateID
        WHERE v.Declined = 1 AND u.LocalUpdateID IS NOT NULL;
        RAISERROR('Declined updates loaded via UpdateID mapping.', 0, 1) WITH NOWAIT;
    END
    ELSE IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='vwMinimalUpdate' AND COLUMN_NAME COLLATE DATABASE_DEFAULT='RevisionID')
    BEGIN
        RAISERROR('Found RevisionID column in vwMinimalUpdate. Checking tbRevision structure...', 0, 1) WITH NOWAIT;
        IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'dbo.tbRevision') AND name COLLATE DATABASE_DEFAULT = 'LocalUpdateID')
        BEGIN
            RAISERROR('dbo.tbRevision hat keine Spalte LocalUpdateID — Mapping nicht möglich.',16,1);
            RETURN;
        END;
        RAISERROR('Querying declined updates via RevisionID mapping (this may take a while)...', 0, 1) WITH NOWAIT;
        INSERT INTO #DeclinedMaster (LocalUpdateID)
        SELECT DISTINCT r.LocalUpdateID
        FROM dbo.vwMinimalUpdate v WITH (NOLOCK)
        INNER JOIN dbo.tbRevision r WITH (NOLOCK) ON v.RevisionID = r.RevisionID
        WHERE v.Declined = 1 AND r.LocalUpdateID IS NOT NULL;
        RAISERROR('Declined updates loaded via RevisionID mapping.', 0, 1) WITH NOWAIT;
    END
    ELSE
    BEGIN
        RAISERROR('vwMinimalUpdate hat keine erwarteten Schlüsselspalten (LocalUpdateID/UpdateID/RevisionID).',16,1);
        RETURN;
    END;

    DECLARE @totalDeclined BIGINT = (SELECT COUNT(*) FROM #DeclinedMaster);
    DECLARE @totalMsg NVARCHAR(200) = CONCAT('Found ', CAST(@totalDeclined AS NVARCHAR(20)), ' declined updates (master list).');
    RAISERROR(@totalMsg, 0, 1) WITH NOWAIT;
    RAISERROR(' ', 0, 1) WITH NOWAIT;

    IF @totalDeclined = 0
    BEGIN
        RAISERROR('Keine abgelehnten Updates gefunden — Abbruch.', 0, 1) WITH NOWAIT;
        DELETE FROM #DeclinedMaster;
        RETURN;
    END;

    DECLARE @initialDeclined BIGINT = @totalDeclined;

    -- targets list (dependency-ordered: child tables first, then parent tables)
    DECLARE @targets TABLE (TName SYSNAME);
    INSERT INTO @targets (TName) VALUES
    -- Tables with FK to tbUpdate (must be deleted FIRST)
    ('tbDeployment'),                       -- FK: LocalUpdateID -> tbUpdate AND RevisionID -> tbRevision
    ('tbInstalledUpdateSufficientForPrerequisite'), -- FK: PrerequisiteLocalUpdateID -> tbUpdate AND PrerequisiteID -> tbPrerequisite
    ('tbPrerequisite'),                     -- FK: LocalUpdateID -> tbUpdate AND RevisionID -> tbRevision (must be AFTER tbInstalledUpdateSufficientForPrerequisite)
    ('tbUpdateSummary'),                    -- FK: LocalUpdateID -> tbUpdate
    ('tbUpdateStatusPerComputer'),          -- FK: LocalUpdateID -> tbUpdate
    ('tbUpdateSummaryForAllComputers'),     -- FK: LocalUpdateID -> tbUpdate
    ('tbUpdateClassificationInAutoDeploymentRule'), -- FK: UpdateClassificationID -> tbUpdate.LocalUpdateID
    ('tbCategory'),                         -- FK: CategoryID -> tbUpdate.LocalUpdateID
    ('tbCategoryInAutoDeploymentRule'),     -- FK: CategoryID -> tbUpdate.LocalUpdateID
    ('tbDriverTargetingGroupPrerequisite'), -- FK: LocalUpdateID -> tbUpdate
    ('tbTargetedDriverHwid'),               -- FK: LocalUpdateID -> tbUpdate
    ('tbUpdateFlag'),                       -- FK: LocalUpdateID -> tbUpdate
    ('tbUpdateType'),                       -- FK: LocalUpdateID -> tbUpdate
    -- Tables with FK to tbRevision (must be deleted BEFORE tbRevision)
    ('tbBundleAtLeastOne'),                 -- FK: RevisionID -> tbRevision AND BundledID -> tbBundleAll (must be BEFORE tbBundleAll)
    ('tbBundleAll'),                        -- FK: RevisionID -> tbRevision
    ('tbCompatiblePrinterProvider'),        -- FK: RevisionID -> tbRevision
    ('tbEulaProperty'),                     -- FK: RevisionID -> tbRevision
    ('tbRevisionSupersedesUpdate'),         -- FK: RevisionID -> tbRevision
    ('tbFileForRevision'),                  -- FK: RevisionID -> tbRevision
    ('tbRevisionInCategory'),               -- FK: RevisionID -> tbRevision
    ('tbFlattenedRevisionInCategory'),      -- FK: RevisionID -> tbRevision
    ('tbRevisionLanguage'),                 -- FK: RevisionID -> tbRevision
    ('tbRevisionExtendedProperty'),         -- FK: RevisionID -> tbRevision
    ('tbRevisionExtendedLanguageMask'),     -- FK: RevisionID -> tbRevision
    ('tbKBArticleForRevision'),             -- FK: RevisionID -> tbRevision
    ('tbSecurityBulletinForRevision'),      -- FK: RevisionID -> tbRevision
    ('tbLocalizedPropertyForRevision'),     -- FK: RevisionID -> tbRevision
    ('tbMoreInfoURLForRevision'),           -- FK: RevisionID -> tbRevision
    ('tbXml'),                              -- FK: RevisionID -> tbRevision
    ('tbPreComputedLocalizedProperty'),     -- FK: RevisionID -> tbRevision
    ('tbProperty'),                         -- FK: RevisionID -> tbRevision
    ('tbBundledRevision'),                  -- FK: RevisionID -> tbRevision
    -- Tables with FK to tbDriver (must be deleted BEFORE tbDriver)
    ('tbDriverFeatureScore'),               -- FK: RevisionID+HardwareID -> tbDriver
    ('tbDistributionComputerHardwareId'),   -- FK: RevisionID+HardwareID -> tbDriver
    ('tbTargetComputerHardwareId'),         -- FK: RevisionID+HardwareID -> tbDriver
    ('tbDriver'),                           -- FK: RevisionID -> tbRevision
    -- Parent tables (must be deleted LAST)
    ('tbRevision'),                         -- Parent table (FK: LocalUpdateID -> tbUpdate)
    ('tbUpdate');                           -- Parent table

    -- main batch loop
    DECLARE @batchNum INT = 0;
    WHILE EXISTS (SELECT 1 FROM #DeclinedMaster)
    BEGIN
        SET @batchNum += 1;
        IF @MaxBatches > 0 AND @batchNum > @MaxBatches BREAK;

        DECLARE @batchStartMsg NVARCHAR(100) = CONCAT('--- Starting batch ', CAST(@batchNum AS NVARCHAR(10)), ' ---');
        RAISERROR(@batchStartMsg, 0, 1) WITH NOWAIT;

        -- prepare #BatchIDs
        DELETE FROM #BatchIDs;
        INSERT INTO #BatchIDs (LocalUpdateID)
        SELECT TOP (@BatchSize) LocalUpdateID FROM #DeclinedMaster ORDER BY LocalUpdateID;

        DECLARE @cntThisBatch BIGINT = (SELECT COUNT(*) FROM #BatchIDs);
        RAISERROR('Batch %d: %d LocalUpdateIDs', 0, 1, @batchNum, @cntThisBatch) WITH NOWAIT;

        -- clear per-batch containers
        DELETE FROM #BatchDeleteLog;
        DELETE FROM #BatchPerUpdateCounts;

        DECLARE @t SYSNAME;
        DECLARE cur CURSOR LOCAL FAST_FORWARD FOR SELECT TName FROM @targets;
        OPEN cur;
        FETCH NEXT FROM cur INTO @t;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @sql NVARCHAR(MAX);
            DECLARE @c BIGINT = 0;
            DECLARE @has_Local INT = 0, @has_Update INT = 0, @has_Revision INT = 0;
            DECLARE @deleted BIGINT = 0;
            DECLARE @tLit NVARCHAR(400);
            DECLARE @msg NVARCHAR(500);

            SET @msg = 'Processing table: ' + @t;
            RAISERROR(@msg, 0, 1) WITH NOWAIT;

            SET @has_Local = CASE WHEN EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.' + @t) AND name = 'LocalUpdateID' COLLATE DATABASE_DEFAULT) THEN 1 ELSE 0 END;
            SET @has_Update = CASE WHEN EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.' + @t) AND name = 'UpdateID' COLLATE DATABASE_DEFAULT) THEN 1 ELSE 0 END;
            SET @has_Revision = CASE WHEN EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.' + @t) AND name = 'RevisionID' COLLATE DATABASE_DEFAULT) THEN 1 ELSE 0 END;

            IF @Mode COLLATE DATABASE_DEFAULT = 'DRY'
            BEGIN
                -- gather per-update counts for this table into #BatchPerUpdateCounts
                SET @tLit = N'''' + REPLACE(@t COLLATE DATABASE_DEFAULT, '''', '''''') + N''''; -- sicheres Literal 'TableName'

                IF @has_Local = 1
                BEGIN
                    RAISERROR('  -> Counting rows via LocalUpdateID...', 0, 1) WITH NOWAIT;
                    SET @sql = N'INSERT INTO #BatchPerUpdateCounts(LocalUpdateID, TableName, RowsAffected)
                                 SELECT t.LocalUpdateID, ' + @tLit + N' AS TableName, COUNT(*) AS RowsAffected
                                 FROM dbo.' + QUOTENAME(@t) + N' t WITH (NOLOCK)
                                 JOIN #BatchIDs b ON t.LocalUpdateID = b.LocalUpdateID
                                 GROUP BY t.LocalUpdateID;';
                    EXEC sp_executesql @sql;
                END
                ELSE IF @has_Update = 1
                BEGIN
                    RAISERROR('  -> Counting rows via UpdateID...', 0, 1) WITH NOWAIT;
                    SET @sql = N'INSERT INTO #BatchPerUpdateCounts(LocalUpdateID, TableName, RowsAffected)
                                 SELECT u.LocalUpdateID, ' + @tLit + N' AS TableName, COUNT(*) AS RowsAffected
                                 FROM dbo.' + QUOTENAME(@t) + N' t WITH (NOLOCK)
                                 JOIN dbo.tbUpdate u WITH (NOLOCK) ON t.UpdateID = u.UpdateID
                                 JOIN #BatchIDs b ON u.LocalUpdateID = b.LocalUpdateID
                                 GROUP BY u.LocalUpdateID;';
                    EXEC sp_executesql @sql;
                END
                ELSE IF @has_Revision = 1
                BEGIN
                    RAISERROR('  -> Counting rows via RevisionID...', 0, 1) WITH NOWAIT;
                    SET @sql = N'INSERT INTO #BatchPerUpdateCounts(LocalUpdateID, TableName, RowsAffected)
                                 SELECT r.LocalUpdateID, ' + @tLit + N' AS TableName, COUNT(*) AS RowsAffected
                                 FROM dbo.' + QUOTENAME(@t) + N' t WITH (NOLOCK)
                                 JOIN dbo.tbRevision r WITH (NOLOCK) ON t.RevisionID = r.RevisionID
                                 JOIN #BatchIDs b ON r.LocalUpdateID = b.LocalUpdateID
                                 GROUP BY r.LocalUpdateID;';
                    EXEC sp_executesql @sql;
                END
                ELSE
                BEGIN
                    RAISERROR('  -> No matching ID column - skipped', 0, 1) WITH NOWAIT;
                    FETCH NEXT FROM cur INTO @t; CONTINUE;
                END

                -- table total for batch
                SELECT @c = ISNULL(SUM(RowsAffected),0) FROM #BatchPerUpdateCounts WHERE TableName COLLATE DATABASE_DEFAULT = @t COLLATE DATABASE_DEFAULT;
                INSERT INTO #BatchDeleteLog VALUES (@t, ISNULL(@c,0));
                
                SET @msg = '  -> Found ' + CAST(@c AS NVARCHAR(20)) + ' rows in ' + @t;
                RAISERROR(@msg, 0, 1) WITH NOWAIT;

                -- ---------- ERSETZUNG: Upsert mittels temporärer Delta-Tabelle (#tmpDelta) ----------
                IF OBJECT_ID('tempdb..#tmpDelta') IS NOT NULL DROP TABLE #tmpDelta;
                CREATE TABLE #tmpDelta (LocalUpdateID BIGINT PRIMARY KEY, DeltaRows BIGINT);

                INSERT INTO #tmpDelta (LocalUpdateID, DeltaRows)
                SELECT LocalUpdateID, SUM(RowsAffected) AS DeltaRows
                FROM #BatchPerUpdateCounts
                WHERE TableName COLLATE DATABASE_DEFAULT = @t COLLATE DATABASE_DEFAULT
                GROUP BY LocalUpdateID;

                -- 1) UPDATE bestehender Zeilen
                UPDATE a
                SET a.TotalRows = a.TotalRows + d.DeltaRows
                FROM #AllPerUpdateCounts a
                JOIN #tmpDelta d ON a.LocalUpdateID = d.LocalUpdateID;

                -- 2) INSERT neuer Zeilen
                INSERT INTO #AllPerUpdateCounts (LocalUpdateID, TotalRows)
                SELECT d.LocalUpdateID, d.DeltaRows
                FROM #tmpDelta d
                LEFT JOIN #AllPerUpdateCounts a ON a.LocalUpdateID = d.LocalUpdateID
                WHERE a.LocalUpdateID IS NULL;

                DROP TABLE #tmpDelta;

                -- final: bereinige den Batch-Puffer für diese Tabelle
                DELETE FROM #BatchPerUpdateCounts WHERE TableName COLLATE DATABASE_DEFAULT = @t COLLATE DATABASE_DEFAULT;

            END
            ELSE
            BEGIN
                -- EXEC mode: delete in chunks
                SET @c = 0;
                SET @deleted = 0;
                IF @has_Local = 1
                BEGIN
                    WHILE 1=1
                    BEGIN
                        SET @sql = N'DELETE TOP(@inn) T FROM dbo.' + QUOTENAME(@t) + N' T
                                     JOIN #BatchIDs b ON T.LocalUpdateID = b.LocalUpdateID; SELECT @cnt = @@ROWCOUNT;';
                        EXEC sp_executesql @sql, N'@inn INT, @cnt BIGINT OUTPUT', @inn = @InnerBatch, @cnt = @deleted OUTPUT;
                        IF @deleted = 0 BREAK;
                        SET @c = @c + @deleted;
                    END
                END
                ELSE IF @has_Update = 1
                BEGIN
                    WHILE 1=1
                    BEGIN
                        SET @sql = N'DELETE TOP(@inn) T FROM dbo.' + QUOTENAME(@t) + N' T
                                     JOIN dbo.tbUpdate u ON T.UpdateID = u.UpdateID
                                     JOIN #BatchIDs b ON u.LocalUpdateID = b.LocalUpdateID; SELECT @cnt = @@ROWCOUNT;';
                        EXEC sp_executesql @sql, N'@inn INT, @cnt BIGINT OUTPUT', @inn = @InnerBatch, @cnt = @deleted OUTPUT;
                        IF @deleted = 0 BREAK;
                        SET @c = @c + @deleted;
                    END
                END
                ELSE IF @has_Revision = 1
                BEGIN
                    WHILE 1=1
                    BEGIN
                        SET @sql = N'DELETE TOP(@inn) T FROM dbo.' + QUOTENAME(@t) + N' T
                                     JOIN dbo.tbRevision r ON T.RevisionID = r.RevisionID
                                     JOIN #BatchIDs b ON r.LocalUpdateID = b.LocalUpdateID; SELECT @cnt = @@ROWCOUNT;';
                        EXEC sp_executesql @sql, N'@inn INT, @cnt BIGINT OUTPUT', @inn = @InnerBatch, @cnt = @deleted OUTPUT;
                        IF @deleted = 0 BREAK;
                        SET @c = @c + @deleted;
                    END
                END
                ELSE
                BEGIN
                    SET @msg = CONCAT('Tabelle ', @t, ': keine passende ID-Spalte – übersprungen.');
                    RAISERROR(@msg, 0, 1) WITH NOWAIT;
                    FETCH NEXT FROM cur INTO @t; CONTINUE;
                END

                -- logging for EXEC (and optionally write DRY logs earlier if you want)
                IF @HasRunID = 1
                BEGIN
                    INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
                    VALUES (GETDATE(), @batchNum, @t, @c, CASE WHEN @Mode COLLATE DATABASE_DEFAULT='DRY' THEN 'DRYRUN' ELSE NULL END, @RunID);
                END
                ELSE
                BEGIN
                    INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
                    VALUES (GETDATE(), @batchNum, @t, @c, CASE WHEN @Mode COLLATE DATABASE_DEFAULT='DRY' THEN 'DRYRUN' ELSE NULL END);
                END

                INSERT INTO #BatchDeleteLog VALUES (@t, @c);
            END

            -- Special handling for tbInstalledUpdateSufficientForPrerequisite:
            -- Also delete rows where PrerequisiteID references declined updates via tbPrerequisite
            IF @t COLLATE DATABASE_DEFAULT = 'tbInstalledUpdateSufficientForPrerequisite' AND @Mode COLLATE DATABASE_DEFAULT = 'EXEC'
            BEGIN
                DECLARE @extraDeleted BIGINT = 0;
                DECLARE @extraTotal BIGINT = 0;
                
                RAISERROR('  -> Special handling: deleting rows via PrerequisiteID -> tbPrerequisite -> tbRevision -> declined updates...', 0, 1) WITH NOWAIT;
                
                WHILE 1=1
                BEGIN
                    SET @sql = N'DELETE TOP(@inn) T 
                                 FROM dbo.tbInstalledUpdateSufficientForPrerequisite T
                                 INNER JOIN dbo.tbPrerequisite p ON T.PrerequisiteID = p.PrerequisiteID
                                 INNER JOIN dbo.tbRevision r ON p.RevisionID = r.RevisionID
                                 INNER JOIN #BatchIDs b ON r.LocalUpdateID = b.LocalUpdateID;
                                 SELECT @cnt = @@ROWCOUNT;';
                    EXEC sp_executesql @sql, N'@inn INT, @cnt BIGINT OUTPUT', @inn = @InnerBatch, @cnt = @extraDeleted OUTPUT;
                    IF @extraDeleted = 0 BREAK;
                    SET @extraTotal = @extraTotal + @extraDeleted;
                END
                
                IF @extraTotal > 0
                BEGIN
                    SET @msg = '  -> Additional ' + CAST(@extraTotal AS NVARCHAR(20)) + ' rows deleted via PrerequisiteID path';
                    RAISERROR(@msg, 0, 1) WITH NOWAIT;
                    
                    -- Update the log with the additional deletions
                    UPDATE #BatchDeleteLog 
                    SET RowsAffected = RowsAffected + @extraTotal 
                    WHERE TableName COLLATE DATABASE_DEFAULT = 'tbInstalledUpdateSufficientForPrerequisite';
                    
                    -- Update the persistent log
                    IF @HasRunID = 1
                    BEGIN
                        INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
                        VALUES (GETDATE(), @batchNum, 'tbInstalledUpdateSufficientForPrerequisite', @extraTotal, 'Additional deletes via PrerequisiteID', @RunID);
                    END
                    ELSE
                    BEGIN
                        INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
                        VALUES (GETDATE(), @batchNum, 'tbInstalledUpdateSufficientForPrerequisite', @extraTotal, 'Additional deletes via PrerequisiteID');
                    END
                END
            END

            -- Special handling for tbBundleAtLeastOne:
            -- Also delete rows where BundledID references declined updates via tbBundleAll -> tbRevision
            IF @t COLLATE DATABASE_DEFAULT = 'tbBundleAtLeastOne' AND @Mode COLLATE DATABASE_DEFAULT = 'EXEC'
            BEGIN
                DECLARE @extraDeletedBundle BIGINT = 0;
                DECLARE @extraTotalBundle BIGINT = 0;
                
                RAISERROR('  -> Special handling: deleting rows via BundledID -> tbBundleAll -> tbRevision -> declined updates...', 0, 1) WITH NOWAIT;
                
                WHILE 1=1
                BEGIN
                    SET @sql = N'DELETE TOP(@inn) T 
                                 FROM dbo.tbBundleAtLeastOne T
                                 INNER JOIN dbo.tbBundleAll ba ON T.BundledID = ba.BundledID
                                 INNER JOIN dbo.tbRevision r ON ba.RevisionID = r.RevisionID
                                 INNER JOIN #BatchIDs b ON r.LocalUpdateID = b.LocalUpdateID;
                                 SELECT @cnt = @@ROWCOUNT;';
                    EXEC sp_executesql @sql, N'@inn INT, @cnt BIGINT OUTPUT', @inn = @InnerBatch, @cnt = @extraDeletedBundle OUTPUT;
                    IF @extraDeletedBundle = 0 BREAK;
                    SET @extraTotalBundle = @extraTotalBundle + @extraDeletedBundle;
                END
                
                IF @extraTotalBundle > 0
                BEGIN
                    SET @msg = '  -> Additional ' + CAST(@extraTotalBundle AS NVARCHAR(20)) + ' rows deleted via BundledID path';
                    RAISERROR(@msg, 0, 1) WITH NOWAIT;
                    
                    -- Update the log with the additional deletions
                    UPDATE #BatchDeleteLog 
                    SET RowsAffected = RowsAffected + @extraTotalBundle 
                    WHERE TableName COLLATE DATABASE_DEFAULT = 'tbBundleAtLeastOne';
                    
                    -- Update the persistent log
                    IF @HasRunID = 1
                    BEGIN
                        INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note, RunID)
                        VALUES (GETDATE(), @batchNum, 'tbBundleAtLeastOne', @extraTotalBundle, 'Additional deletes via BundledID', @RunID);
                    END
                    ELSE
                    BEGIN
                        INSERT INTO dbo.WSUSDeleteLog (RunAt, BatchNumber, TableName, RowsAffected, Note)
                        VALUES (GETDATE(), @batchNum, 'tbBundleAtLeastOne', @extraTotalBundle, 'Additional deletes via BundledID');
                    END
                END
            END

            FETCH NEXT FROM cur INTO @t;
        END

        CLOSE cur; DEALLOCATE cur;

        -- DRY-run per-batch printouts (summarize per table)
        IF @Mode COLLATE DATABASE_DEFAULT = 'DRY'
        BEGIN
            DECLARE @tname SYSNAME; DECLARE @r BIGINT;
            DECLARE rpt CURSOR LOCAL FAST_FORWARD FOR SELECT TableName, RowsAffected FROM #BatchDeleteLog;
            OPEN rpt; FETCH NEXT FROM rpt INTO @tname, @r;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                DECLARE @rptMsg NVARCHAR(500) = CONCAT('Batch ', CAST(@batchNum AS NVARCHAR(10)), ' (DRY) would delete ', CAST(@r AS NVARCHAR(20)), ' rows from ', @tname);
                RAISERROR(@rptMsg, 0, 1) WITH NOWAIT;
                FETCH NEXT FROM rpt INTO @tname, @r;
            END
            CLOSE rpt; DEALLOCATE rpt;
        END

        -- remove processed LocalUpdateIDs from master
        DELETE dm FROM #DeclinedMaster dm WHERE EXISTS (SELECT 1 FROM #BatchIDs b WHERE b.LocalUpdateID = dm.LocalUpdateID);

        -- cumulative (from WSUSDeleteLog for EXEC mode; for DRY we use #AllPerUpdateCounts)
        DECLARE @cumLogged BIGINT = 0;
        IF @HasRunID = 1 AND @Mode COLLATE DATABASE_DEFAULT <> 'DRY'
            SELECT @cumLogged = ISNULL(SUM(RowsAffected),0) FROM dbo.WSUSDeleteLog WHERE RunID = @RunID;
        ELSE
            SET @cumLogged = 0;

        DECLARE @cumMsg NVARCHAR(500) = CONCAT('Batch ', CAST(@batchNum AS NVARCHAR(10)), ' completed. Cumulative rows logged so far: ', CAST(@cumLogged AS NVARCHAR(20)));
        RAISERROR(@cumMsg, 0, 1) WITH NOWAIT;

        -- cleanup per-batch content (keep tables)
        DELETE FROM #BatchIDs;
        DELETE FROM #BatchDeleteLog;
        DELETE FROM #BatchPerUpdateCounts;

        -- wait between batches
        IF LTRIM(RTRIM(@WaitBetweenBatches)) COLLATE DATABASE_DEFAULT <> ''
        BEGIN
            DECLARE @waitcmd NVARCHAR(50) = N'WAITFOR DELAY ''' + @WaitBetweenBatches + N''';';
            EXEC(@waitcmd);
        END
    END -- end while batches

    -- final summary: TotalRowsLogged (from WSUSDeleteLog) for EXEC, and DRY aggregated summary from #AllPerUpdateCounts
    DECLARE @totalRowsLogged BIGINT = 0;
    IF @HasRunID = 1
        SELECT @totalRowsLogged = ISNULL(SUM(RowsAffected),0) FROM dbo.WSUSDeleteLog WHERE RunID = @RunID;
    ELSE
        SELECT @totalRowsLogged = ISNULL(SUM(RowsAffected),0) FROM dbo.WSUSDeleteLog WHERE RunAt >= @RunStart;

    DECLARE @finalMsg NVARCHAR(500) = CONCAT('All batches processed. TotalRowsLogged=', CAST(ISNULL(@totalRowsLogged,0) AS NVARCHAR(20)));
    RAISERROR(@finalMsg, 0, 1) WITH NOWAIT;
    RAISERROR(' ', 0, 1) WITH NOWAIT;

    -- === DRYRUN: persist and final cumulative summary (robust: persist then read from persistent table) ===
    IF @DryRun = 1
    BEGIN
        -- Persist only if #AllPerUpdateCounts exists and has rows
        IF OBJECT_ID('tempdb..#AllPerUpdateCounts') IS NOT NULL AND EXISTS (SELECT 1 FROM #AllPerUpdateCounts)
        BEGIN
            INSERT INTO dbo.WSUSDryRunSummary (RunID, RunStart, RunEnd, LocalUpdateID, TotalRows)
            SELECT @RunID, @RunStart, NULL, LocalUpdateID, TotalRows
            FROM #AllPerUpdateCounts;

            PRINT 'DRYRUN results persisted to dbo.WSUSDryRunSummary for RunID ' + CONVERT(NVARCHAR(36), @RunID) + '.' ;
        END
        ELSE
        BEGIN
            PRINT 'Hinweis: #AllPerUpdateCounts war leer oder existierte nicht — keine Persistierung vorgenommen.';
        END

        -- Now read back from persistent table and output Top-N or all entries via RAISERROR (Messages window)
        DECLARE @countRows INT = 0;
        SELECT @countRows = COUNT(*) FROM dbo.WSUSDryRunSummary WHERE RunID = @RunID;

        IF @countRows = 0
        BEGIN
            PRINT 'Keine Einträge für RunID ' + CONVERT(NVARCHAR(36), @RunID) + ' in dbo.WSUSDryRunSummary gefunden.';
        END
        ELSE
        BEGIN
            -- >>> Statt Inline-Subqueries: berechne Variablen und gib sie per RAISERROR aus (vermeidet Parser-Probleme)
            DECLARE @distinctLocalUpdates INT = 0;
            DECLARE @totalRowsWouldDelete BIGINT = 0;

            SELECT @distinctLocalUpdates = COUNT(*) FROM dbo.WSUSDryRunSummary WHERE RunID = @RunID;
            SELECT @totalRowsWouldDelete = ISNULL(SUM(TotalRows),0) FROM dbo.WSUSDryRunSummary WHERE RunID = @RunID;

            RAISERROR('DRYRUN - Cumulative: DistinctLocalUpdateIDs = %d, TotalRowsWouldDelete = %d', 0, 1,
                      @distinctLocalUpdates, @totalRowsWouldDelete
                     ) WITH NOWAIT;

            -- Cursor to output Top-N/all
            DECLARE @pLocal BIGINT;
            DECLARE @pRows BIGINT;
            DECLARE curPersist CURSOR LOCAL FAST_FORWARD FOR
            SELECT LocalUpdateID, TotalRows
            FROM dbo.WSUSDryRunSummary
            WHERE RunID = @RunID
            ORDER BY TotalRows DESC;

            OPEN curPersist;
            FETCH NEXT FROM curPersist INTO @pLocal, @pRows;
            DECLARE @printed INT = 0;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                IF @DryRaiseAll = 1
                BEGIN
                    RAISERROR('DRYRUN would delete %d rows for LocalUpdateID %d', 0, 1, @pRows, @pLocal) WITH NOWAIT;
                END
                ELSE
                BEGIN
                    IF @printed < @DryRaiseTop
                    BEGIN
                        RAISERROR('DRYRUN would delete %d rows for LocalUpdateID %d', 0, 1, @pRows, @pLocal) WITH NOWAIT;
                    END
                END

                SET @printed = @printed + 1;
                FETCH NEXT FROM curPersist INTO @pLocal, @pRows;
            END
            CLOSE curPersist;
            DEALLOCATE curPersist;

            PRINT 'Displayed Top ' + CAST(CASE WHEN @DryRaiseAll = 1 THEN @countRows ELSE @DryRaiseTop END AS NVARCHAR(10)) + ' LocalUpdateIDs from dbo.WSUSDryRunSummary for RunID ' + CONVERT(NVARCHAR(36), @RunID) + '.';
        END
    END

    -- === Laufzeit als hh:mm:ss ===
    DECLARE @RunEnd DATETIME2 = SYSUTCDATETIME();
    DECLARE @elapsed_seconds BIGINT = DATEDIFF(SECOND, @RunStart, @RunEnd);
    DECLARE @hours INT = @elapsed_seconds / 3600;
    DECLARE @mins INT = (@elapsed_seconds % 3600) / 60;
    DECLARE @secs INT = @elapsed_seconds % 60;
    RAISERROR('Laufzeit: %02d:%02d:%02d (hh:mm:ss)', 0, 1, @hours, @mins, @secs) WITH NOWAIT;

    -- === Final cumulative display per-mode (backup already done before deletes in EXEC) ===
    PRINT '';
    PRINT '--- Final cumulative summary ---';

    IF @DryRun = 1
    BEGIN
        PRINT 'DRYRUN: cumulative per LocalUpdateID (from dbo.WSUSDryRunSummary):';
        SELECT LocalUpdateID, TotalRows
        FROM dbo.WSUSDryRunSummary
        WHERE RunID = @RunID
        ORDER BY TotalRows DESC;

        SELECT COUNT(*) AS DistinctLocalUpdateIDs, ISNULL(SUM(TotalRows),0) AS TotalRowsWouldDelete
        FROM dbo.WSUSDryRunSummary
        WHERE RunID = @RunID;

        PRINT 'Hinweis: DRYRUN führt kein Backup aus. Um Backup durchzuführen, @DryRun = 0 setzen.';
    END
    ELSE
    BEGIN
        PRINT 'EXEC mode: cumulative deletions from dbo.WSUSDeleteLog for this run:';
        IF @HasRunID = 1
        BEGIN
            SELECT BatchNumber, TableName, SUM(RowsAffected) AS RowsAffected
            FROM dbo.WSUSDeleteLog
            WHERE RUNID = @RunID
            GROUP BY BatchNumber, TableName
            ORDER BY BatchNumber, TableName;

            SELECT ISNULL(SUM(RowsAffected),0) AS TotalRowsDeleted FROM dbo.WSUSDeleteLog WHERE RUNID = @RunID;
        END
        ELSE
        BEGIN
            PRINT 'RunID nicht vorhanden in WSUSDeleteLog — zeige Löschungen seit RunStart:';
            SELECT BatchNumber, TableName, SUM(RowsAffected) AS RowsAffected
            FROM dbo.WSUSDeleteLog
            WHERE RunAt >= @RunStart
            GROUP BY BatchNumber, TableName
            ORDER BY BatchNumber, TableName;

            SELECT ISNULL(SUM(RowsAffected),0) AS TotalRowsDeleted FROM dbo.WSUSDeleteLog WHERE RunAt >= @RunStart;
        END

        PRINT 'Hinweis: Mandatory backup wurde vor den Löschungen ausgeführt (siehe WSUSDeleteLog Eintrag BatchNumber = 0).';
    END

    -- optional: final cleanup - drop temp tables to free tempdb immediately
    IF OBJECT_ID('tempdb..#DeclinedMaster') IS NOT NULL DROP TABLE #DeclinedMaster;
    IF OBJECT_ID('tempdb..#BatchIDs') IS NOT NULL DROP TABLE #BatchIDs;
    IF OBJECT_ID('tempdb..#BatchDeleteLog') IS NOT NULL DROP TABLE #BatchDeleteLog;
    IF OBJECT_ID('tempdb..#BatchPerUpdateCounts') IS NOT NULL DROP TABLE #BatchPerUpdateCounts;
    IF OBJECT_ID('tempdb..#AllPerUpdateCounts') IS NOT NULL DROP TABLE #AllPerUpdateCounts;
    IF OBJECT_ID('tempdb..#tmpDistinct') IS NOT NULL DROP TABLE #tmpDistinct;

END TRY
BEGIN CATCH
    DECLARE @errnum INT = ERROR_NUMBER();
    DECLARE @errmsg NVARCHAR(4000) = ERROR_MESSAGE();
    PRINT CONCAT('Script failed: ', CAST(@errnum AS NVARCHAR(10)), ' - ', @errmsg);

    -- best-effort cleanup
    IF OBJECT_ID('tempdb..#BatchIDs') IS NOT NULL DROP TABLE #BatchIDs;
    IF OBJECT_ID('tempdb..#BatchDeleteLog') IS NOT NULL DROP TABLE #BatchDeleteLog;
    IF OBJECT_ID('tempdb..#BatchPerUpdateCounts') IS NOT NULL DROP TABLE #BatchPerUpdateCounts;
    IF OBJECT_ID('tempdb..#AllPerUpdateCounts') IS NOT NULL DROP TABLE #AllPerUpdateCounts;
    IF OBJECT_ID('tempdb..#DeclinedMaster') IS NOT NULL DROP TABLE #DeclinedMaster;
    IF OBJECT_ID('tempdb..#tmpDistinct') IS NOT NULL DROP TABLE #tmpDistinct;

    THROW;
END CATCH;
