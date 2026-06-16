# Repair-SharePointNames.ps1
# Processes only items flagged by SPMT in the migration-warnings.csv.
# Moves temp/system files (~$ lock files, desktop.ini) to a quarantine folder instead of deleting.
# Renames files with invalid SharePoint characters.
# Use -WhatIf to preview all changes without making them.
#
# Usage:
#   .\Repair-SharePointNames.ps1 -CsvPath ".\migration-warnings.csv" -RootPath "\\main\sys\BIN" -QuarantinePath "C:\SPMigration\Quarantine" -WhatIf
#   .\Repair-SharePointNames.ps1 -CsvPath ".\migration-warnings.csv" -RootPath "\\main\sys\BIN" -QuarantinePath "C:\SPMigration\Quarantine"

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [Parameter(Mandatory=$true)]
    [string]$RootPath,

    [string]$QuarantinePath = "",

    [switch]$WhatIf
)

# Characters invalid in SharePoint Online
$InvalidCharsPattern = '["*:<>?/\\|]'

# Replacement character
$Replacement = '-'

# Files that should be deleted rather than renamed
$DeletePatterns = @(
    '^~\$',       # Office lock files (~$filename)
    '^~of',       # Office temp files (~ofXXXX.tmp)
    '^desktop\.ini$',
    '\.idlk$',    # InDesign lock files
    '^~.*\.tmp$'  # Temp files starting with ~
)

function Should-Delete {
    param([string]$Name)
    foreach ($pattern in $DeletePatterns) {
        if ($Name -match $pattern) { return $true }
    }
    return $false
}

function Get-CleanName {
    param([string]$Name)
    $ext = [System.IO.Path]::GetExtension($Name)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $cleanBase = $base -replace $InvalidCharsPattern, $Replacement
    $cleanBase = $cleanBase.Trim(' ')
    $cleanBase = $cleanBase.TrimEnd('.')
    return "$cleanBase$ext"
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    Write-Error "CSV not found: $CsvPath"
    exit 1
}

if ($WhatIf) {
    Write-Output "*** WHATIF MODE - No changes will be made ***"
    Write-Output ""
}

# Validate QuarantinePath
if (-not $WhatIf) {
    if ($QuarantinePath -eq "") {
        Write-Error "You must specify -QuarantinePath when not running in WhatIf mode."
        exit 1
    }
    if (-not (Test-Path -LiteralPath $QuarantinePath)) {
        New-Item -ItemType Directory -Path $QuarantinePath -Force | Out-Null
        Write-Output "Created quarantine directory: $QuarantinePath"
    }
} else {
    if ($QuarantinePath -eq "") {
        $QuarantinePath = "C:\SPMigration\Quarantine (example)"
    }
}

# Load only INVALID_SHAREPOINT_NAME rows for the specified root path
$entries = Import-Csv -Path $CsvPath | Where-Object {
    $_.'Issue' -eq 'INVALID_SHAREPOINT_NAME' -and
    $_.'SourcePath' -like "$RootPath*"
}

Write-Output "Found $($entries.Count) flagged item(s) under $RootPath"
Write-Output ""

$deleted = 0
$renamed = 0
$skipped = 0
$errors  = 0

foreach ($entry in $entries) {
    $fullPath = $entry.'SourcePath'
    $name     = $entry.'Name'

    if (-not (Test-Path -LiteralPath $fullPath)) {
        Write-Warning "Not found (may already be resolved): $fullPath"
        $skipped++
        continue
    }

    if (Should-Delete -Name $name) {
        # Build mirror path under quarantine directory
        $relativePath = $fullPath.Substring($RootPath.TrimEnd('\').Length).TrimStart('\')
        $destPath = Join-Path $QuarantinePath $relativePath

        if ($WhatIf) {
            Write-Output "MOVE: $fullPath"
            Write-Output "  TO: $destPath"
            Write-Output ""
            $deleted++
        } else {
            try {
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                attrib -s -h -r $fullPath
                Move-Item -LiteralPath $fullPath -Destination $destPath -Force -ErrorAction Stop
                Write-Output "Moved: $fullPath"
                Write-Output "   To: $destPath"
                $deleted++
            } catch {
                Write-Warning "Failed to move '$fullPath': $_"
                $errors++
            }
        }
    } else {
        $newName = Get-CleanName -Name $name
        if ($newName -eq $name) {
            Write-Output "SKIP (name already valid): $name"
            $skipped++
            continue
        }

        $parentDir = Split-Path $fullPath -Parent
        $newPath   = Join-Path $parentDir $newName

        if ($WhatIf) {
            Write-Output "RENAME: $fullPath"
            Write-Output "    TO: $newPath"
            Write-Output ""
            $renamed++
        } else {
            try {
                Rename-Item -LiteralPath $fullPath -NewName $newName -ErrorAction Stop
                Write-Output "Renamed: $name -> $newName"
                $renamed++
            } catch {
                Write-Warning "Failed to rename '$fullPath': $_"
                $errors++
            }
        }
    }
}

Write-Output ""
Write-Output "--- Summary ---"
if ($WhatIf) {
    Write-Output "Would move to quarantine: $deleted"
    Write-Output "Would rename:             $renamed"
    Write-Output "Would skip:               $skipped"
    if ($QuarantinePath -ne "") {
        Write-Output "Quarantine path:          $QuarantinePath"
    }
} else {
    Write-Output "Moved to quarantine: $deleted"
    Write-Output "Renamed:             $renamed"
    Write-Output "Skipped:             $skipped"
    Write-Output "Errors:              $errors"
    Write-Output "Quarantine path:     $QuarantinePath"
}
