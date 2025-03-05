Param (
    [Parameter()][String]$Encrypt = 'Optional'
)

function Get-WSUSSQLInstance {
    $wsusSetupKey = "HKLM:\SOFTWARE\Microsoft\Update Services\Server\Setup"
    if (Test-Path $wsusSetupKey) {
        $wsusSetup = Get-ItemProperty -Path $wsusSetupKey -ErrorAction SilentlyContinue
        if ($wsusSetup -and $wsusSetup.SqlServerName) {
            return $wsusSetup.SqlServerName
        }
    }
    Write-Error "SQL-Instanz für WSUS konnte nicht ermittelt werden. Bitte stellen Sie sicher, dass der Registrierungsschlüssel vorhanden ist und den Wert SqlServerName enthält."
    exit 1
}

$SQLServerInstance = Get-WSUSSQLInstance
Write-Verbose "Verwende SQL Server Instanz: $SQLServerInstance"

# Erfordert das SqlServer PowerShell-Modul (mindestens Version 16.5.0)
Import-Module SqlServer -MinimumVersion 16.5.0

$ClientProductVersions = @(
    @{ ProductVersion = ' 8';   OSMajorVersion = 6; OSMinorVersion = 2; OSBuildNumber = 9200 },
    @{ ProductVersion = ' 8.1'; OSMajorVersion = 6; OSMinorVersion = 3; OSBuildNumber = 9600 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1507'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 10240 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1511'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 10586 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1607'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 14393 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1703'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 15063 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1709'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 16299 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1803'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 17134 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1809'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 17763 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1903'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 18362 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 1909'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 18363 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 2004'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19041 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 20H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19042 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 21H1'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19043 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 21H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19044 },
    @{ ProductVersion = ' 10';  ProductRelease = ' 22H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19045 },
    @{ ProductVersion = ' 11';  ProductRelease = ' 21H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 22000 },
    @{ ProductVersion = ' 11';  ProductRelease = ' 22H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 22621 },
    @{ ProductVersion = ' 11';  ProductRelease = ' 23H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 22631 },
    @{ ProductVersion = ' 11';  ProductRelease = ' 24H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 26100 }
)

$ServerProductVersions = @(
    @{ ProductVersion = ' 2012';      OSMajorVersion = 6; OSMinorVersion = 2; OSBuildNumber = 9200 },
    @{ ProductVersion = ' 2012 R2';   OSMajorVersion = 6; OSMinorVersion = 3; OSBuildNumber = 9600 },
    @{ ProductVersion = ' 2016';      OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 14393 },
    @{ ProductVersion = ', version 1709'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 16299 },
    @{ ProductVersion = ', version 1803'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 17134 },
    @{ ProductVersion = ' 2019';      OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 17763 },
    @{ ProductVersion = ', version 1903'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 18362 },
    @{ ProductVersion = ', version 1909'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 18363 },
    @{ ProductVersion = ', version 2004'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19041 },
    @{ ProductVersion = ', version 20H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 19042 },
    @{ ProductVersion = ' 2022';      OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 20348 },
    @{ ProductVersion = ', version 23H2'; OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 25398 },
    @{ ProductVersion = ' 2025';      OSMajorVersion = 10; OSMinorVersion = 0; OSBuildNumber = 26100 }
)

$OSDescriptions = @(
    @{ 
        ProductName = 'Windows'; 
        ProductVersions = $ClientProductVersions; 
        ProductTypes = @(
            @{ ProductEdition = ' S';                   NewProductTypes = @(178) },
            @{ ProductEdition = ' S N';                 NewProductTypes = @(179) },
            @{ ProductEdition = ' Pro N';               NewProductTypes = @(49) },
            @{ ProductEdition = ' SE';                  NewProductTypes = @(203) },
            @{ ProductEdition = ' SE N';                NewProductTypes = @(202) },
            @{ ProductEdition = ' Home';                NewProductTypes = @(101, 111) },
            @{ ProductEdition = ' Home China';          NewProductTypes = @(99) },
            @{ ProductEdition = ' Home N';              NewProductTypes = @(98) },
            @{ ProductEdition = ' Home Single Language'; NewProductTypes = @(100) },
            @{ ProductEdition = ' Education';           NewProductTypes = @(121) },
            @{ ProductEdition = ' Education N';         NewProductTypes = @(122) },
            @{ ProductEdition = ' Enterprise';          NewProductTypes = @(4) },
            @{ ProductEdition = ' Enterprise Evaluation'; NewProductTypes = @(72) },
            @{ ProductEdition = ' Enterprise G';          NewProductTypes = @(171) },
            @{ ProductEdition = ' Enterprise G N';        NewProductTypes = @(172) },
            @{ ProductEdition = ' Enterprise N';          NewProductTypes = @(27) },
            @{ ProductEdition = ' Enterprise N Evaluation'; NewProductTypes = @(84) },
            @{ ProductEdition = ' Enterprise LTSC';       NewProductTypes = @(125) },
            @{ ProductEdition = ' Enterprise LTSC Evaluation'; NewProductTypes = @(129) },
            @{ ProductEdition = ' Enterprise LTSC N';     NewProductTypes = @(126) },
            @{ ProductEdition = ' Enterprise LTSC N Evaluation'; NewProductTypes = @(130) },
            @{ ProductEdition = ' Holographic';           NewProductTypes = @(135) },
            @{ ProductEdition = ' Holographic for Business'; NewProductTypes = @(136) },
            @{ ProductEdition = ' IoT Core';              NewProductTypes = @(123) },
            @{ ProductEdition = ' IoT Core Commercial';   NewProductTypes = @(131) },
            @{ ProductEdition = ' IoT Enterprise';        NewProductTypes = @(188) },
            @{ ProductEdition = ' IoT Enterprise LTSC';     NewProductTypes = @(191) },
            @{ ProductEdition = ' Mobile';                NewProductTypes = @(104) },
            @{ ProductEdition = ' Mobile Enterprise';     NewProductTypes = @(133) },
            @{ ProductEdition = ' Team';                  NewProductTypes = @(119) },
            @{ ProductEdition = ' Pro';                   NewProductTypes = @(48) },
            @{ ProductEdition = ' Pro Education';         NewProductTypes = @(164) },
            @{ ProductEdition = ' Pro Education N';       NewProductTypes = @(165) },
            @{ ProductEdition = ' Pro for Workstations';  NewProductTypes = @(161) },
            @{ ProductEdition = ' Pro for Workstations N'; NewProductTypes = @(162) },
            @{ ProductEdition = ' Pro China';             NewProductTypes = @(139) },
            @{ ProductEdition = ' Pro Single Language';   NewProductTypes = @(138) },
            @{ ProductEdition = ' Enterprise multi-session'; NewProductTypes = @(175) }
        ) 
    },
    @{ 
        ProductName = 'Windows RT'; 
        ProductVersions = $ClientProductVersions; 
        ProductTypes = @(
            @{ ProductEdition = ''; NewProductTypes = @(97) }
        ) 
    },
    @{ 
        ProductName = 'Windows Server'; 
        ProductVersions = $ServerProductVersions; 
        ProductTypes = @(
            @{ ProductEdition = ' Standard';              NewProductTypes = @(7, 13) },
            @{ ProductEdition = ' Standard Evaluation';     NewProductTypes = @(79, 160) },
            @{ ProductEdition = ' Datacenter';              NewProductTypes = @(8, 12) },
            @{ ProductEdition = ' Datacenter Evaluation';   NewProductTypes = @(80, 159) },
            @{ ProductEdition = ' Datacenter: Azure Edition'; NewProductTypes = @(407) },
            @{ ProductEdition = ' Foundation';              NewProductTypes = @(33) },
            @{ ProductEdition = ' Essentials';              NewProductTypes = @(50) }
        ) 
    },
    @{ 
        ProductName = 'Microsoft Hyper-V Server'; 
        ProductVersions = $ServerProductVersions; 
        ProductTypes = @(
            @{ ProductEdition = ''; NewProductTypes = @(42) }
        ) 
    }
)

$SqlcmdQuery = "USE [SUSDB]"

foreach ($OSDescription in $OSDescriptions) {
    foreach ($ProductVersion in $OSDescription.ProductVersions) {
        foreach ($ProductType in $OSDescription.ProductTypes) {
            foreach ($NewProductType in $ProductType.NewProductTypes) {
                $FullOSDescription = "$($OSDescription.ProductName)$($ProductVersion.ProductVersion)$($ProductType.ProductEdition)$($ProductVersion.ProductRelease)"
                $SqlcmdQuery += "`r`n" + (('UPDATE [dbo].[tbComputerTargetDetail]',
                    "SET [OSDescription] = `'$FullOSDescription`'",
                    'WHERE',
                    "[OSMajorVersion] = $($ProductVersion.OSMajorVersion)",
                    'AND',
                    "[OSMinorVersion] = $($ProductVersion.OSMinorVersion)",
                    'AND',
                    "[OSBuildNumber] = $($ProductVersion.OSBuildNumber)",
                    'AND',
                    "[NewProductType] = $($NewProductType)",
                    'AND',
                    "( [OSDescription] <> `'$FullOSDescription`' OR [OSDescription] IS NULL )") -join "`r`n")
            }
        }
    }
}

Invoke-Sqlcmd -ServerInstance $SQLServerInstance -Encrypt $Encrypt -Query $SqlcmdQuery -Verbose 4>&1 | Tee-Object -FilePath "$env:ProgramFiles\Update Services\Update-WSUSComputerOperatingSystems.log"
