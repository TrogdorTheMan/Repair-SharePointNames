# Repair-SharePointNames

A PowerShell script that resolves file-level warnings produced by the **SharePoint Migration Tool (SPMT)** before migrating Windows file shares to SharePoint Online. It operates strictly off SPMT's own scan logs — it never independently scans the filesystem — so only items SPMT actually flagged are touched.

## Background

When migrating on-premises file shares to SharePoint Online using SPMT, the tool will run an assessment scan and flag items it cannot migrate as-is. Two common warning types are:

- **INVALID_SHAREPOINT_NAME** — the file or folder name contains a character that SharePoint Online does not permit (`" * : < > ? / \ |`)
- **ITEM_IS_EMPTY** — a file is zero bytes or a folder contains no files (SPMT can be configured to skip these automatically)

This script addresses `INVALID_SHAREPOINT_NAME` items by either renaming them (replacing invalid characters with `-`) or quarantining them (moving them to a holding directory outside the migration scope).

## Workflow

### Step 1 — Run the SPMT Assessment Scan

In the SharePoint Admin Center, go to **Migration > SharePoint Migration Tool** and run an assessment scan against your file shares. Once complete, export the detailed scan logs (CSV format, one per source path).

### Step 2 — Generate migration-warnings.csv

Parse the raw SPMT scan log CSVs into a single consolidated warnings file. You can do this with any script or tool that filters rows where `ResultCode` equals `INVALID_SHAREPOINT_NAME`. The output CSV should have at minimum these columns:

| Column | Description |
|---|---|
| `RootPath` | The share root (e.g. `\\server\share\folder`) |
| `SourcePath` | Full UNC path to the flagged item |
| `Name` | Filename or folder name |
| `Type` | `File` or `Folder` |
| `Issue` | `INVALID_SHAREPOINT_NAME` or `ITEM_IS_EMPTY` |
| `SizeBytes` | File size in bytes |
| `LastModified` | Last modified timestamp |

Place `migration-warnings.csv` in the same directory as the script.

### Step 3 — Preview Changes with -WhatIf

Always run with `-WhatIf` first to see exactly what the script will do before making any changes:

```powershell
.\Repair-SharePointNames.ps1 `
    -CsvPath ".\migration-warnings.csv" `
    -RootPath "\\server\share\folder" `
    -QuarantinePath "C:\SPMigration\Quarantine" `
    -WhatIf
```

Output will show each action as either `MOVE` (for lock files and system files) or `RENAME` (for files with invalid characters), along with the destination path. Redirect to a file to review before committing:

```powershell
.\Repair-SharePointNames.ps1 -CsvPath ".\migration-warnings.csv" -RootPath "\\server\share\folder" -QuarantinePath "C:\SPMigration\Quarantine" -WhatIf | Out-File ".\whatif-results.txt"
```

### Step 4 — Run the Repair

Once you're satisfied with the WhatIf output, run without `-WhatIf`:

```powershell
.\Repair-SharePointNames.ps1 `
    -CsvPath ".\migration-warnings.csv" `
    -RootPath "\\server\share\folder" `
    -QuarantinePath "C:\SPMigration\Quarantine"
```

Process one root path at a time. The script will:

- **Quarantine** Office lock files (`~$*`), InDesign lock files (`*.idlk`), Office temp files (`~of*`, `~*.tmp`), and `desktop.ini` — moving them to `QuarantinePath` while preserving the relative folder structure
- **Rename** any remaining files or folders whose names contain invalid SharePoint characters, replacing them with `-`
- **Strip hidden/system attributes** (`attrib -s -h -r`) from lock files before moving, since these are often hidden system-attributed files that would otherwise block the operation

### Step 5 — Re-run the SPMT Scan

After repairs are complete, re-run the SPMT assessment scan on the same paths to confirm the warning count has dropped to zero. If new warnings appear, export the updated scan logs and repeat the process.

### Step 6 — Migrate

Once the scan passes cleanly, proceed with the full migration in SPMT.

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `-CsvPath` | Yes | Path to `migration-warnings.csv` generated from SPMT scan logs |
| `-RootPath` | Yes | The source share root to process (e.g. `\\server\share\HR`) — must match the value in the CSV |
| `-QuarantinePath` | Yes (unless -WhatIf) | Local or UNC path where quarantined files will be moved. Created automatically if it doesn't exist. |
| `-WhatIf` | No | Preview mode — no files are moved or renamed |

## What Gets Quarantined vs. Renamed

Files matching any of these patterns are **moved to quarantine** rather than renamed:

| Pattern | Type |
|---|---|
| `~$*` | Microsoft Office lock files (open document indicators) |
| `~of*` | Office temp files |
| `~*.tmp` | Temp files starting with `~` |
| `desktop.ini` | Windows shell configuration files |
| `*.idlk` | Adobe InDesign lock files |

These files serve no purpose in SharePoint — they are transient artifacts that exist only while a document is open on a workstation. They are moved rather than deleted so you have a recovery path if needed.

Everything else with a name containing `" * : < > ? / \ |` is **renamed** with those characters replaced by `-`.

## Notes

- The script is compatible with **PowerShell 3.0** and later (suitable for Windows Server 2012 without upgrades)
- All output uses `Write-Output` rather than `Write-Host`, so it can be captured with `Out-File`
- Empty files and folders (`ITEM_IS_EMPTY`) are not processed by this script — configure SPMT to skip items smaller than 1 KB to handle zero-byte files automatically
- Run the script directly on the server hosting the shares, or from any machine with UNC access to the paths

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE) for details.
