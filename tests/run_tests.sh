#!/usr/bin/env bash
# Builds mock sources, deploys sql/ into BATEEL_RPT, loads as of 2026-10-05,
# then runs the assertions. Needs sqlcmd and a disposable SQL Server.
#   SQLCMD="sqlcmd -C -S localhost -U sa -P <password>" tests/run_tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQLCMD="${SQLCMD:?set SQLCMD to your sqlcmd invocation}"

run() { $SQLCMD -b -I "$@"; }

run -d master -i "$ROOT/tests/mock_sources.sql"
for f in "$ROOT"/sql/*.sql; do
    echo "deploy $(basename "$f")"
    run -d BATEEL_RPT -i "$f"
done
run -d BATEEL_RPT -Q "EXEC rpt.usp_LoadSales @AsOfDate = '2026-10-05';"
run -d BATEEL_RPT -W -s '|' -i "$ROOT/tests/assertions.sql"
