"""End-to-end test: patched SQL on the mock BC databases -> build -> check the embedded data.

    SALES_SQL_SERVER=localhost SALES_SQL_USER=sa SALES_SQL_PASSWORD=... python tests/test_pipeline.py

Needs a disposable SQL Server already loaded with tests/mock_sources.sql (repo root) and
pipeline/tests/mock_extract_addon.sql, and the pymssql or pyodbc driver.
"""
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIPE = HERE.parent


def build(cfg_overrides: dict, out: Path, *extra) -> subprocess.CompletedProcess:
    cfg = json.loads((PIPE / "config.example.json").read_text())
    cfg["connection"].update({"driver": "pymssql"})
    cfg["output_dir"] = str(out)
    cfg.update(cfg_overrides)
    cfg_path = out / "config.json"
    cfg_path.write_text(json.dumps(cfg))
    return subprocess.run([sys.executable, str(PIPE / "build_dashboard.py"), "--config", str(cfg_path),
                           "--as-of", "2026-10-06", *extra], capture_output=True, text=True)


def data_of(html_path: Path) -> dict:
    blob = re.search(r'<script id="dash-data" type="application/json">(.*?)</script>', html_path.read_text(), re.S).group(1)
    return json.loads(blob.replace("<\\/", "</"))


def line_sum(d, kind, month, **f):
    i = d["months"].index(month)
    return sum(L[kind][i] for L in d["lines"] if all(L[k] == v for k, v in f.items()))


def main():
    failures = []

    def check(name, actual, expected, tol=1):
        ok = actual is not None and abs(actual - expected) <= tol
        print(f"{'PASS' if ok else 'FAIL'}  {name}: expected {expected}, got {actual}")
        if not ok:
            failures.append(name)

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp)
        r = build({}, out)
        print(r.stdout, r.stderr)
        if r.returncode != 0:
            print("FAIL  build failed"); sys.exit(1)
        g = data_of(out / "sales-dashboard-group.html")

        check("Months start 1 Jan last year", int(g["months"][0] == "2025-01"), 1, 0)
        check("Months run to Dec this year", int(g["months"][-1] == "2026-12"), 1, 0)
        check("UAE Sep actual positive, counted once (FIX 4 + sign)", line_sum(g, "act", "2026-09", co="UAE"), 2000)
        check("UAE RETAIL Sep excludes the airline sale", line_sum(g, "act", "2026-09", co="UAE", seg="RETAIL"), 1000)
        check("UAE AIRLINES Sep", line_sum(g, "act", "2026-09", co="UAE", seg="AIRLINES"), 500)
        check("Mixed-case 'Franchise' Division_ID now included (FIX 3)", line_sum(g, "act", "2026-09", seg="FRANCHISE"), 200)
        check("Dept 1196 -> ECOM via rule", line_sum(g, "act", "2026-09", seg="ECOM"), 300)
        check("Quantity positive (UAE RETAIL Sep)", line_sum(g, "qty", "2026-09", co="UAE", seg="RETAIL"), 10)
        check("KSA RETAIL in AED", line_sum(g, "act", "2026-09", co="KSA", seg="RETAIL"), 979)
        check("KSA dept 3193 -> B2B", line_sum(g, "act", "2026-09", co="KSA", seg="B2B"), 98)
        check("Fakhra 014 -> Jomara Distributor KSA", line_sum(g, "act", "2026-09", co="FAKHRA", sub="Jomara Distributor — KSA"), 979)
        check("Fakhra padded 017 -> Private Label", line_sum(g, "act", "2026-09", sub="KSA Private Label"), 29)
        check("LY (Sep 2025) UAE RETAIL loaded (FIX 1)", line_sum(g, "act", "2025-09", co="UAE", seg="RETAIL"), 900)
        check("Budget UAE RETAIL Sep, no double count", line_sum(g, "bud", "2026-09", co="UAE", seg="RETAIL"), 2000)
        check("Budget AIRLINES from cust-cat block", line_sum(g, "bud", "2026-09", seg="AIRLINES"), 600)
        check("Future budget month loaded (FIX 2)", line_sum(g, "bud", "2026-12", co="UAE"), 2400)
        check("Other Income separate, not in budget (FIX 5)", line_sum(g, "oi", "2026-09", co="UAE"), 80)
        cov = {c["co"]: c["months"] for c in g["dq"]["budget_coverage"]}
        check("Fakhra budget name mismatch shows 0 months", cov.get("FAKHRA"), 0, 0)
        check("Provisional rule hit recorded (017)", int(any("017" in p["rule"] for p in g["dq"]["provisional"])), 1, 0)

        rt = data_of(out / "sales-dashboard-retail.html")
        check("Retail file holds only RETAIL lines", int(all(L["seg"] == "RETAIL" for L in rt["lines"])), 1, 0)
        check("Retail file holds no Fakhra data", int(not any(L["co"] == "FAKHRA" for L in rt["lines"])), 1, 0)
        check("Retail file hides unassigned list", len(rt["dq"]["unassigned"]), 0, 0)
        jm = data_of(out / "sales-dashboard-jomara-uae.html")
        check("Jomara UAE file has no KSA sub-lines", int(all(L["co"] == "UAE" for L in jm["lines"])), 1, 0)
        check("Jomara UAE file SKUs scoped", int(all(b["co"] == "UAE" and b["seg"] == "JOMARA" for s in jm["skus"] for b in s["by"])), 1, 0)

        # Sign guard: a wrong multiplier must stop the build
        bad = build({"sign": {"sales": 1, "quantity": 1}}, out)
        check("Wrong sign config aborts the build", bad.returncode, 2, 0)
        print("      ", bad.stderr.strip())

    print(f"\n{'ALL PASSED' if not failures else f'{len(failures)} FAILED'}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
