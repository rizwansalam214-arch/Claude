# Nightly build, for Windows Task Scheduler. Run as the read-only service account.
#   Program: powershell.exe   Arguments: -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\pipeline\run_nightly.ps1"
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot
$env:SALES_SQL_SERVER = "YOUR-SQL-HOST"          # or set it once as a machine environment variable
$log = Join-Path $PSScriptRoot ("output\build_{0:yyyyMMdd_HHmm}.log" -f (Get-Date))
New-Item -ItemType Directory -Force -Path (Join-Path $PSScriptRoot "output") | Out-Null
python build_dashboard.py *>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { throw "Dashboard build failed (exit $LASTEXITCODE). See $log" }
# Keep 30 days of raw extracts; they contain full sales detail.
Get-ChildItem (Join-Path $PSScriptRoot "output") -Filter "extract_*" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item
