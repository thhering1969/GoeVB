USE [SUSDB];
GO

-- Optional: Löschen Sie den Trigger, falls er bereits existiert, um ihn neu zu erstellen
IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'trg_UpdateOSDescriptionOnInsert')
BEGIN
    DROP TRIGGER [dbo].[trg_UpdateOSDescriptionOnInsert];
    PRINT 'Bestehender Trigger [trg_UpdateOSDescriptionOnInsert] wurde gelöscht.';
END
GO

PRINT 'Erstelle Trigger [trg_UpdateOSDescriptionOnInsert]...';
GO

CREATE TRIGGER [dbo].[trg_UpdateOSDescriptionOnInsert]
   ON  [dbo].[tbComputerTargetDetail]
   AFTER INSERT
AS 
BEGIN
    -- Verhindert, dass "rows affected"-Meldungen an die WSUS-Anwendung gesendet werden
    SET NOCOUNT ON;

    -- Definieren Sie alle Produktversionen und Editionszuordnungen
    WITH VersionMap (ProductName, OSMajorVersion, OSMinorVersion, OSBuildNumber, ProductVersion, ProductRelease) AS (
        -- $ClientProductVersions
        SELECT 'Windows', 6, 2, 9200, ' 8', '' UNION ALL
        SELECT 'Windows', 6, 3, 9600, ' 8.1', '' UNION ALL
        SELECT 'Windows', 10, 0, 10240, ' 10', ' 1507' UNION ALL
        SELECT 'Windows', 10, 0, 10586, ' 10', ' 1511' UNION ALL
        SELECT 'Windows', 10, 0, 14393, ' 10', ' 1607' UNION ALL
        SELECT 'Windows', 10, 0, 15063, ' 10', ' 1703' UNION ALL
        SELECT 'Windows', 10, 0, 16299, ' 10', ' 1709' UNION ALL
        SELECT 'Windows', 10, 0, 17134, ' 10', ' 1803' UNION ALL
        SELECT 'Windows', 10, 0, 17763, ' 10', ' 1809' UNION ALL
        SELECT 'Windows', 10, 0, 18362, ' 10', ' 1903' UNION ALL
        SELECT 'Windows', 10, 0, 18363, ' 10', ' 1909' UNION ALL
        SELECT 'Windows', 10, 0, 19041, ' 10', ' 2004' UNION ALL
        SELECT 'Windows', 10, 0, 19042, ' 10', ' 20H2' UNION ALL
        SELECT 'Windows', 10, 0, 19043, ' 10', ' 21H1' UNION ALL
        SELECT 'Windows', 10, 0, 19044, ' 10', ' 21H2' UNION ALL
        SELECT 'Windows', 10, 0, 19045, ' 10', ' 22H2' UNION ALL
        SELECT 'Windows', 10, 0, 22000, ' 11', ' 21H2' UNION ALL
        SELECT 'Windows', 10, 0, 22621, ' 11', ' 22H2' UNION ALL
        SELECT 'Windows', 10, 0, 22631, ' 11', ' 23H2' UNION ALL
        SELECT 'Windows', 10, 0, 26100, ' 11', ' 24H2' UNION ALL
        SELECT 'Windows', 10, 0, 26200, ' 11', ' 25H2' UNION ALL
        SELECT 'Windows RT', 6, 2, 9200, ' 8', '' UNION ALL
        SELECT 'Windows RT', 6, 3, 9600, ' 8.1', '' UNION ALL
        SELECT 'Windows RT', 10, 0, 10240, ' 10', ' 1507' UNION ALL
        SELECT 'Windows RT', 10, 0, 10586, ' 10', ' 1511' UNION ALL
        SELECT 'Windows RT', 10, 0, 14393, ' 10', ' 1607' UNION ALL
        SELECT 'Windows RT', 10, 0, 15063, ' 10', ' 1703' UNION ALL
        SELECT 'Windows RT', 10, 0, 16299, ' 10', ' 1709' UNION ALL
        SELECT 'Windows RT', 10, 0, 17134, ' 10', ' 1803' UNION ALL
        SELECT 'Windows RT', 10, 0, 17763, ' 10', ' 1809' UNION ALL
        SELECT 'Windows RT', 10, 0, 18362, ' 10', ' 1903' UNION ALL
        SELECT 'Windows RT', 10, 0, 18363, ' 10', ' 1909' UNION ALL
        SELECT 'Windows RT', 10, 0, 19041, ' 10', ' 2004' UNION ALL
        SELECT 'Windows RT', 10, 0, 19042, ' 10', ' 20H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 19043, ' 10', ' 21H1' UNION ALL
        SELECT 'Windows RT', 10, 0, 19044, ' 10', ' 21H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 19045, ' 10', ' 22H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 22000, ' 11', ' 21H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 22621, ' 11', ' 22H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 22631, ' 11', ' 23H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 26100, ' 11', ' 24H2' UNION ALL
        SELECT 'Windows RT', 10, 0, 26200, ' 11', ' 25H2' UNION ALL
        -- $ServerProductVersions
        SELECT 'Windows Server', 6, 2, 9200, ' 2012', '' UNION ALL
        SELECT 'Windows Server', 6, 3, 9600, ' 2012 R2', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 14393, ' 2016', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 16299, ', version 1709', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 17134, ', version 1803', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 17763, ' 2019', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 18362, ', version 1903', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 18363, ', version 1909', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 19041, ', version 2004', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 19042, ', version 20H2', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 20348, ' 2022', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 25398, ', version 23H2', '' UNION ALL
        SELECT 'Windows Server', 10, 0, 26100, ' 2025', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 6, 2, 9200, ' 2012', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 6, 3, 9600, ' 2012 R2', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 14393, ' 2016', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 16299, ', version 1709', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 17134, ', version 1803', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 17763, ' 2019', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 18362, ', version 1903', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 18363, ', version 1909', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 19041, ', version 2004', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 19042, ', version 20H2', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 20348, ' 2022', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 25398, ', version 23H2', '' UNION ALL
        SELECT 'Microsoft Hyper-V Server', 10, 0, 26100, ' 2025', '' UNION ALL
        -- $AzureStackHCIProductVersions
        SELECT 'Microsoft Azure Stack HCI', 10, 0, 17784, ', version 20H2', '' UNION ALL
        SELECT 'Microsoft Azure Stack HCI', 10, 0, 20348, ', version 21H2', '' UNION ALL
        SELECT 'Microsoft Azure Stack HCI', 10, 0, 20349, ', version 22H2', '' UNION ALL
        SELECT 'Microsoft Azure Stack HCI', 10, 0, 25398, ', version 23H2', '' UNION ALL
        SELECT 'Microsoft Azure Stack HCI', 10, 0, 26100, ', version 24H2', ''
    ),
    EditionMap (ProductName, ProductEdition, NewProductType) AS (
        -- Windows Editions
        SELECT 'Windows', ' S', 178 UNION ALL
        SELECT 'Windows', ' S N', 179 UNION ALL
        SELECT 'Windows', ' Pro N', 49 UNION ALL
        SELECT 'Windows', ' SE', 203 UNION ALL
        SELECT 'Windows', ' SE N', 202 UNION ALL
        SELECT 'Windows', ' Home', 101 UNION ALL
        SELECT 'Windows', ' Home', 111 UNION ALL
        SELECT 'Windows', ' Home China', 99 UNION ALL
        SELECT 'Windows', ' Home N', 98 UNION ALL
        SELECT 'Windows', ' Home Single Language', 100 UNION ALL
        SELECT 'Windows', ' Education', 121 UNION ALL
        SELECT 'Windows', ' Education N', 122 UNION ALL
        SELECT 'Windows', ' Enterprise', 4 UNION ALL
        SELECT 'Windows', ' Enterprise Evaluation', 72 UNION ALL
        SELECT 'Windows', ' Enterprise G', 171 UNION ALL
        SELECT 'Windows', ' Enterprise G N', 172 UNION ALL
        SELECT 'Windows', ' Enterprise N', 27 UNION ALL
        SELECT 'Windows', ' Enterprise N Evaluation', 84 UNION ALL
        SELECT 'Windows', ' Enterprise LTSC', 125 UNION ALL
        SELECT 'Windows', ' Enterprise LTSC Evaluation', 129 UNION ALL
        SELECT 'Windows', ' Enterprise LTSC N', 126 UNION ALL
        SELECT 'Windows', ' Enterprise LTSC N Evaluation', 130 UNION ALL
        SELECT 'Windows', ' Holographic', 135 UNION ALL
        SELECT 'Windows', ' Holographic for Business', 136 UNION ALL
        SELECT 'Windows', ' IoT Core', 123 UNION ALL
        SELECT 'Windows', ' IoT Core Commercial', 131 UNION ALL
        SELECT 'Windows', ' IoT Enterprise', 188 UNION ALL
        SELECT 'Windows', ' IoT Enterprise LTSC', 191 UNION ALL
        SELECT 'Windows', ' Mobile', 104 UNION ALL
        SELECT 'Windows', ' Mobile Enterprise', 133 UNION ALL
        SELECT 'Windows', ' Team', 119 UNION ALL
        SELECT 'Windows', ' Pro', 48 UNION ALL
        SELECT 'Windows', ' Pro Education', 164 UNION ALL
        SELECT 'Windows', ' Pro Education N', 165 UNION ALL
        SELECT 'Windows', ' Pro for Workstations', 161 UNION ALL
        SELECT 'Windows', ' Pro for Workstations N', 162 UNION ALL
        SELECT 'Windows', ' Pro China', 139 UNION ALL
        SELECT 'Windows', ' Pro Single Language', 138 UNION ALL
        SELECT 'Windows', ' Enterprise multi-session', 175 UNION ALL
        -- Windows RT Edition
        SELECT 'Windows RT', '', 97 UNION ALL
        -- Windows Server Editions
        SELECT 'Windows Server', ' Standard', 7 UNION ALL
        SELECT 'Windows Server', ' Standard', 13 UNION ALL
        SELECT 'Windows Server', ' Standard Evaluation', 79 UNION ALL
        SELECT 'Windows Server', ' Standard Evaluation', 160 UNION ALL
        SELECT 'Windows Server', ' Datacenter', 8 UNION ALL
        SELECT 'Windows Server', ' Datacenter', 12 UNION ALL
        SELECT 'Windows Server', ' Datacenter Evaluation', 80 UNION ALL
        SELECT 'Windows Server', ' Datacenter Evaluation', 159 UNION ALL
        SELECT 'Windows Server', ' Datacenter: Azure Edition', 407 UNION ALL
        SELECT 'Windows Server', ' Datacenter: Azure Edition Core', 408 UNION ALL
        SELECT 'Windows Server', ' Foundation', 33 UNION ALL
        SELECT 'Windows Server', ' Essentials', 50 UNION ALL
        -- Microsoft Hyper-V Server Edition
        SELECT 'Microsoft Hyper-V Server', '', 42 UNION ALL
        -- Microsoft Azure Stack HCI Edition
        SELECT 'Microsoft Azure Stack HCI', '', 406
    ),
    FullMap (OSMajorVersion, OSMinorVersion, OSBuildNumber, NewProductType, FullOSDescription) AS (
        -- Kombinieren Sie die Zuordnungen, um die endgültige Beschreibungszeichenfolge zu erstellen
        SELECT
            V.OSMajorVersion,
            V.OSMinorVersion,
            V.OSBuildNumber,
            E.NewProductType,
            (V.ProductName + V.ProductVersion + E.ProductEdition + V.ProductRelease) AS FullOSDescription
        FROM VersionMap AS V
        JOIN EditionMap AS E ON V.ProductName = E.ProductName
    )
    -- Führen Sie das endgültige UPDATE durch
    UPDATE T
    SET
        T.OSDescription = M.FullOSDescription
    FROM
        [dbo].[tbComputerTargetDetail] AS T
    JOIN
        FullMap AS M ON T.OSMajorVersion = M.OSMajorVersion
                    AND T.OSMinorVersion = M.OSMinorVersion
                    AND T.OSBuildNumber = M.OSBuildNumber
                    AND T.NewProductType = M.NewProductType
    -- **** HIER IST DIE WICHTIGSTE ÄNDERUNG ****
    -- Joine mit der 'inserted'-Tabelle, um NUR die neu eingefügten Zeilen zu aktualisieren.
    -- Der Primärschlüssel 'TargetID' wird für den Join verwendet.
    JOIN
        inserted AS i ON T.TargetID = i.TargetID
    WHERE
        -- Stellen Sie sicher, dass wir nicht unnötig aktualisieren (obwohl bei INSERT 'OSDescription' wahrscheinlich NULL ist)
        (T.OSDescription IS NULL OR T.OSDescription <> M.FullOSDescription);

END
GO

PRINT 'Trigger [trg_UpdateOSDescriptionOnInsert] wurde erfolgreich erstellt.';
GO