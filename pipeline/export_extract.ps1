# Runs the patched extract on your network and saves a zipped CSV you can upload.
#   .\export_extract.ps1 -Server "YOUR-SQL-HOST"
# Needs the SqlServer PowerShell module once:  Install-Module SqlServer -Scope CurrentUser
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [string]$Database = "BTL_LS_LIVE"
)
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd_HHmm"
New-Item -ItemType Directory -Force -Path "output" | Out-Null
$csv = "output\extract_$stamp.csv"

Write-Host "Running extract on $Server / $Database (read-only, may take several minutes)..."
$started = Get-Date
Invoke-Sqlcmd -ServerInstance $Server -Database $Database -InputFile "sql\channel_sku_extract.sql" `
    -QueryTimeout 0 -MaxCharLength 4000 -TrustServerCertificate |
    Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8

@{ extracted_at = $started.ToString("s"); sql_file = "sql/channel_sku_extract.sql" } |
    ConvertTo-Json | Set-Content "output\extract_$stamp.meta.json"
Compress-Archive -Path $csv, "output\extract_$stamp.meta.json" -DestinationPath "output\extract_$stamp.zip" -Force
$rows = (Get-Content $csv | Measure-Object -Line).Lines - 1
Write-Host ("Done: {0:N0} rows in {1:N0}s -> output\extract_{2}.zip" -f $rows, ((Get-Date) - $started).TotalSeconds, $stamp)
