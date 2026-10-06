#!/usr/bin/env python3
"""Extract -> transform -> render the Sales & SKU dashboard.

    python build_dashboard.py                      # run the SQL, build every audience
    python build_dashboard.py --audience retail    # one audience only
    python build_dashboard.py --from-csv output/extract_20261006_0215.csv   # rebuild without the database

Steps:
  1. Extract   run sql/channel_sku_extract.sql (read-only) and save the raw rows as CSV.
  2. Transform fix signs, convert SAR -> AED, map every row to one segment / sub-line,
               aggregate to month x company x segment x sub-line and month x SKU.
  3. Validate  abort if sales or quantity come out negative overall; collect data-quality findings.
  4. Render    inject the data into template.html, one file per audience, each holding only
               that audience's segments and companies.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

REQUIRED_COLUMNS = [
    "Company", "Source Type", "Month Start", "Division", "Department Code", "Department",
    "Customer Category Code", "SKU", "Item Description", "Base Unit of Measure",
    "ItemCat", "Sales", "Quantity", "Other Income", "Sales Budget",
]
# Division labels the query gives UAE customer-category BUDGET rows (their Department Code holds the cust. cat.)
CUSTCAT_BUDGET_LABELS = {"AIRLINES", "HOTELS", "JOMARASUPERMARKETS", "JOMARADISTRIBUTION", "DUTYFREE",
                         "JOMARAEXPORTS", "CORPORATESINSTS"}


class BuildError(Exception):
    pass


# ----------------------------------------------------------------------------- config
def load_config(path: Path) -> dict:
    if not path.exists():
        raise BuildError(f"Config not found: {path}. Copy config.example.json to config.json first.")
    with path.open(encoding="utf-8") as f:
        return json.load(f)


# ----------------------------------------------------------------------------- extract
def connect(cfg: dict):
    c = cfg["connection"]
    server = os.environ.get(c["server_env"])
    if not server:
        raise BuildError(f"Set the {c['server_env']} environment variable to the SQL Server host.")
    user = os.environ.get(c.get("user_env", ""), "")
    pwd = os.environ.get(c.get("password_env", ""), "")
    if c.get("driver", "pyodbc") == "pymssql":
        import pymssql  # optional fallback driver
        return pymssql.connect(server=server, user=user, password=pwd, database=c["database"],
                               timeout=c.get("timeout_seconds", 1800), login_timeout=30)
    import pyodbc
    parts = [f"DRIVER={{{c['odbc_driver']}}}", f"SERVER={server}", f"DATABASE={c['database']}",
             f"Encrypt={c.get('encrypt', 'yes')}", f"TrustServerCertificate={c.get('trust_server_certificate', 'no')}",
             "ApplicationIntent=ReadOnly"]
    parts += ["Trusted_Connection=yes"] if c.get("trusted_connection") else [f"UID={user}", f"PWD={pwd}"]
    conn = pyodbc.connect(";".join(parts), timeout=30)
    conn.timeout = c.get("timeout_seconds", 1800)
    return conn


def sql_batches(sql: str) -> list[str]:
    """Split on GO lines (a client-side separator, not T-SQL)."""
    return [b.strip() for b in re.split(r"^\s*GO\s*;?\s*$", sql, flags=re.I | re.M) if b.strip()]


def extract(cfg: dict, out_dir: Path) -> tuple[Path, dt.datetime]:
    sql = (HERE / cfg["sql_file"]).read_text(encoding="utf-8")
    batches = sql_batches(sql)
    started = dt.datetime.now()
    print(f"[extract] connecting to {os.environ.get(cfg['connection']['server_env'])} / {cfg['connection']['database']}")
    conn = connect(cfg)
    cur = conn.cursor()
    for b in batches[:-1]:
        cur.execute(b)
    cur.execute("SET NOCOUNT ON;\n" + batches[-1])
    while cur.description is None:          # skip DECLARE / rowcount results if the driver surfaces them
        if not cur.nextset():
            raise BuildError("The query returned no result set.")
    cols = [d[0] for d in cur.description]
    stamp = started.strftime("%Y%m%d_%H%M")
    path = out_dir / f"extract_{stamp}.csv"
    n = 0
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        while True:
            rows = cur.fetchmany(20000)
            if not rows:
                break
            for r in rows:
                w.writerow(["" if v is None else (v.isoformat() if hasattr(v, "isoformat") else v) for v in r])
            n += len(rows)
            print(f"[extract] {n:,} rows", end="\r")
    conn.close()
    secs = (dt.datetime.now() - started).total_seconds()
    (out_dir / f"extract_{stamp}.meta.json").write_text(json.dumps(
        {"extracted_at": started.isoformat(timespec="seconds"), "rows": n, "seconds": round(secs, 1),
         "sql_file": cfg["sql_file"]}, indent=2))
    print(f"[extract] {n:,} rows in {secs:.0f}s -> {path.name}")
    return path, started


# ----------------------------------------------------------------------------- transform
def norm_label(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Z0-9]", "", s.upper())


def num(v) -> float:
    if v is None or v == "":
        return 0.0
    try:
        return float(v)
    except ValueError:
        raise BuildError(f"Non-numeric value in a numeric column: {v!r}")


def month_key(row: dict) -> str:
    """YYYY-MM from the query's YearMonth column, else from Month Start in ISO or dd/mm/yyyy form
    (PowerShell Export-Csv and SSMS write dates in the machine's locale)."""
    ym = (row.get("YearMonth") or "").strip()
    if re.fullmatch(r"\d{4}-\d{2}", ym):
        return ym
    v = str(row.get("Month Start") or "").strip()
    if re.match(r"\d{4}-\d{2}", v):
        return v[:7]
    m = re.match(r"(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})", v)
    if m:
        return f"{m.group(3)}-{int(m.group(2)):02d}"     # dd/mm/yyyy (UAE / UK locale)
    raise BuildError(f"Cannot read the month from Month Start {v!r}")


def month_range(first: str, last: str) -> list[str]:
    y, m = int(first[:4]), int(first[5:7])
    out = []
    while f"{y:04d}-{m:02d}" <= last:
        out.append(f"{y:04d}-{m:02d}")
        m += 1
        if m > 12:
            y, m = y + 1, 1
    return out


class Resolver:
    """Maps one row to (segment, sub-line, order, rule id, provisional). Precedence:
    UAE customer category -> department code -> division label -> UNASSIGNED."""

    def __init__(self, rules: dict):
        self.cc = {k: v for k, v in rules["uae_customer_category"].items() if not k.startswith("_")}
        self.dept = {co: {k: v for k, v in m.items()} for co, m in rules["department"].items() if not co.startswith("_")}
        self.div = {k: v for k, v in rules["division"].items() if not k.startswith("_")}

    def resolve(self, co: str, src: str, division: str, dept: str, custcat: str):
        ndiv = norm_label(division)
        if co == "UAE":
            cc = custcat
            # Budget rows from the customer-category block carry the cust. cat. in Department Code
            if src == "BUDGET" and not cc and ndiv in CUSTCAT_BUDGET_LABELS and dept in self.cc:
                cc = dept
            if cc and cc in self.cc:
                r = self.cc[cc]
                return r["segment"], r["subline"], r.get("order"), f"UAE cust. cat. {cc}", bool(r.get("provisional"))
        r = self.dept.get(co, {}).get(dept)
        if r:
            return r["segment"], r["subline"], r.get("order"), f"{co} dept {dept}", bool(r.get("provisional"))
        r = self.div.get(ndiv)
        if r:
            return r["segment"], r["subline"], r.get("order"), f"division {ndiv}", bool(r.get("provisional"))
        return None, None, None, None, False


def transform(cfg: dict, csv_path: Path, as_of: dt.date) -> dict:
    res = Resolver(cfg["rules"])
    fx = cfg["fx_to_aed"]
    s_sign, q_sign = cfg["sign"]["sales"], cfg["sign"]["quantity"]

    lines = {}                                   # (co, seg, sub) -> {order, codes, cells: {(kind, month): v}}
    skus = {}                                    # sku -> {desc, cat, uom, cells: {(seg, co, kind, month): v}}
    unassigned = defaultdict(float)
    provisional = defaultdict(float)
    counts = defaultdict(int)
    raw = {"sales": 0.0, "qty": 0.0, "budget": 0.0, "oi": 0.0}
    months_seen = set()
    no_cat = set()

    with csv_path.open(newline="", encoding="utf-8-sig") as f:
        rd = csv.DictReader(f)
        missing = [c for c in REQUIRED_COLUMNS if c not in (rd.fieldnames or [])]
        if missing:
            raise BuildError(f"Extract is missing columns: {', '.join(missing)}")
        for row in rd:
            co = (row["Company"] or "").strip().upper()
            src = (row["Source Type"] or "").strip().upper()
            m = month_key(row)
            months_seen.add(m)
            counts[src] += 1
            if co not in fx:
                raise BuildError(f"No FX rate configured for company {co!r}")
            rate = fx[co]
            dept = (row["Department Code"] or "").strip()
            cc = (row["Customer Category Code"] or "").strip()
            seg, sub, order, rule, prov = res.resolve(co, src, row["Division"] or "", dept, cc)

            if src in ("CUSTOMER CATEGORY", "DIVISION"):
                sales_raw, qty_raw = num(row["Sales"]), num(row["Quantity"])
                raw["sales"] += sales_raw
                raw["qty"] += qty_raw
                v, q = sales_raw * s_sign * rate, qty_raw * q_sign
                kind_vals = [("act", v), ("qty", q)]
            elif src == "BUDGET":
                v = num(row["Sales Budget"]) * rate
                raw["budget"] += num(row["Sales Budget"])
                kind_vals = [("bud", v)]
            elif src == "OTHER INCOME":
                v = num(row["Other Income"]) * rate
                raw["oi"] += num(row["Other Income"])
                kind_vals = [("oi", v)]
            else:
                counts["UNKNOWN SOURCE: " + src] += 1
                continue

            if seg is None:
                key = (src, co, row["Division"] or "", dept, cc)
                unassigned[key] += kind_vals[0][1]
                continue
            if prov:
                provisional[(rule, src)] += kind_vals[0][1]

            L = lines.setdefault((co, seg, sub), {"order": order, "cells": defaultdict(float)})
            for kind, val in kind_vals:
                L["cells"][(kind, m)] += val

            if src in ("CUSTOMER CATEGORY", "DIVISION") and row["SKU"]:
                no = row["SKU"].strip()
                cat = (row.get("ItemCat") or "").strip()
                if not cat:
                    no_cat.add(no)
                S = skus.setdefault(no, {"desc": (row["Item Description"] or "").strip(), "cat": cat or "Uncategorised",
                                         "uom": (row["Base Unit of Measure"] or "").strip(), "cells": defaultdict(float)})
                for kind, val in kind_vals:
                    S["cells"][(seg, co, kind, m)] += val

    if not months_seen:
        raise BuildError("The extract is empty.")

    # ---- validation: sign
    act_total = raw["sales"] * s_sign
    qty_total = raw["qty"] * q_sign
    if act_total <= 0 or qty_total <= 0:
        raise BuildError(
            f"Sign check failed: actual sales {act_total:,.0f} / quantity {qty_total:,.0f} after applying "
            f"config sign {s_sign}/{q_sign}. Run diagnostics/01_sign_check.sql and set config 'sign' accordingly.")

    first = min(min(months_seen), f"{as_of.year - 1}-01")     # always from 1 Jan last year
    last = f"{as_of.year}-12"
    months = month_range(first, max(last, max(months_seen)))
    idx = {k: i for i, k in enumerate(months)}

    def series(cells, kind, *prefix):
        out = [0] * len(months)
        for key, v in cells.items():
            if key[:-1] == (*prefix, kind):
                out[idx[key[-1]]] = round(v)
        return out

    line_rows = []
    for (co, seg, sub), L in lines.items():
        line_rows.append({"co": co, "seg": seg, "sub": sub, "order": L["order"],
                          **{k: series(L["cells"], k) for k in ("act", "qty", "bud", "oi")}})

    sku_rows = []
    for no, S in skus.items():
        combos = sorted({(k[0], k[1]) for k in S["cells"]})
        by = []
        for seg, co in combos:
            act = series(S["cells"], "act", seg, co)
            qty = series(S["cells"], "qty", seg, co)
            if any(act) or any(qty):
                by.append({"seg": seg, "co": co, "act": act, "qty": qty})
        if by:
            sku_rows.append({"no": no, "desc": S["desc"], "cat": S["cat"], "uom": S["uom"], "by": by})

    coverage = []
    for co in fx:
        bud_months = sorted({months[i] for L in line_rows if L["co"] == co for i, v in enumerate(L["bud"]) if v})
        coverage.append({"co": co, "months": len(bud_months), "first": bud_months[0] if bud_months else None,
                         "last": bud_months[-1] if bud_months else None,
                         "total": round(sum(sum(L["bud"]) for L in line_rows if L["co"] == co))})

    return {
        "months": months,
        "lines": line_rows,
        "skus": sku_rows,
        "dq": {
            "row_counts": dict(counts),
            "sign": {"sales_raw": round(raw["sales"]), "sales_after": round(act_total),
                     "qty_raw": round(raw["qty"]), "qty_after": round(qty_total), "multipliers": [s_sign, q_sign]},
            "unassigned": sorted(({"source": k[0], "co": k[1], "division": k[2], "dept": k[3], "custcat": k[4],
                                   "amount": round(v)} for k, v in unassigned.items() if round(v)),
                                 key=lambda r: -abs(r["amount"]))[:200],
            "provisional": [{"rule": k[0], "source": k[1], "amount": round(v)} for k, v in sorted(provisional.items())],
            "budget_coverage": coverage,
            "skus_without_category": len(no_cat),
        },
    }


# ----------------------------------------------------------------------------- render
def scope_filter(data: dict, aud: dict) -> dict:
    segs = None if aud["segments"] == "*" else set(aud["segments"])
    cos = None if aud["companies"] == "*" else set(aud["companies"])
    keep = lambda seg, co: (segs is None or seg in segs) and (cos is None or co in cos)
    lines = [L for L in data["lines"] if keep(L["seg"], L["co"])]
    skus = []
    for s in data["skus"]:
        by = [b for b in s["by"] if keep(b["seg"], b["co"])]
        if by:
            skus.append({**s, "by": by})
    dq = dict(data["dq"])
    if not aud.get("group"):
        # Unassigned rows have no segment; only group users may see them. Coverage limited to own companies.
        dq["unassigned"] = []
        dq["provisional"] = []
        dq["budget_coverage"] = [c for c in dq["budget_coverage"] if cos is None or c["co"] in cos]
        dq["row_counts"] = {}
    return {"months": data["months"], "lines": lines, "skus": skus, "dq": dq}


def render(cfg: dict, data: dict, aud_key: str, as_of: dt.date, extracted_at: str, out_dir: Path) -> Path:
    aud = cfg["audiences"][aud_key]
    payload = scope_filter(data, aud)
    seg_codes = [s["code"] for s in cfg["segments"]]
    payload["segments"] = [s for s in cfg["segments"] if aud["segments"] == "*" or s["code"] in aud["segments"]]
    payload["meta"] = {
        "as_of": as_of.isoformat(),
        "extracted_at": extracted_at,
        "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
        "audience": {"key": aud_key, "label": aud["label"], "group": bool(aud.get("group")),
                     "segments": seg_codes if aud["segments"] == "*" else aud["segments"],
                     "companies": list(cfg["fx_to_aed"]) if aud["companies"] == "*" else aud["companies"]},
        "fx": cfg["fx_to_aed"],
        "source": cfg["sql_file"],
        "analyst": bool(cfg.get("analyst_enabled")),
    }
    blob = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
    tpl = (HERE / cfg["template"]).read_text(encoding="utf-8")
    if "/*__DASHBOARD_DATA__*/" not in tpl:
        raise BuildError("Template is missing the /*__DASHBOARD_DATA__*/ placeholder.")
    html = tpl.replace("/*__DASHBOARD_DATA__*/", blob)
    path = out_dir / f"sales-dashboard-{aud_key}.html"
    path.write_text(html, encoding="utf-8")
    print(f"[render] {aud['label']}: {len(payload['lines'])} lines, {len(payload['skus'])} SKUs, "
          f"{len(html) / 1e6:.1f} MB -> {path.name}")
    return path


# ----------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(HERE / "config.json"))
    ap.add_argument("--from-csv", help="Skip the database and rebuild from a saved extract CSV.")
    ap.add_argument("--as-of", help="As-of date YYYY-MM-DD (default: extract time, or today).")
    ap.add_argument("--audience", action="append", help="Audience key from config (repeatable). Default: all.")
    a = ap.parse_args(argv)

    try:
        cfg = load_config(Path(a.config))
        out_dir = (HERE / cfg["output_dir"]).resolve()
        out_dir.mkdir(parents=True, exist_ok=True)

        if a.from_csv:
            csv_path = Path(a.from_csv).resolve()
            meta_path = csv_path.with_suffix(".meta.json")
            extracted_at = json.loads(meta_path.read_text())["extracted_at"] if meta_path.exists() else \
                dt.datetime.fromtimestamp(csv_path.stat().st_mtime).isoformat(timespec="seconds")
        else:
            try:
                csv_path, started = extract(cfg, out_dir)
            except BuildError:
                raise
            except Exception as e:  # driver / network errors: one readable line, no traceback
                raise BuildError(f"Database step failed: {str(e).splitlines()[0][:300]}. Check the server name, "
                                 "network access and login, or run with --from-csv on an exported file.")
            extracted_at = started.isoformat(timespec="seconds")
        as_of = dt.date.fromisoformat(a.as_of) if a.as_of else dt.date.fromisoformat(extracted_at[:10])

        print(f"[transform] {csv_path.name}, as of {as_of}")
        data = transform(cfg, csv_path, as_of)
        dq = data["dq"]
        print(f"[validate] sign OK (sales AED-equivalent {dq['sign']['sales_after']:,}); "
              f"{len(dq['unassigned'])} unassigned groups; {len(dq['provisional'])} provisional rule hits")
        for c in dq["budget_coverage"]:
            if c["months"] == 0:
                print(f"[validate] WARNING: no budget loaded for {c['co']} (check the budget name)")

        audiences = a.audience or [k for k in cfg["audiences"] if not k.startswith("_")]
        for k in audiences:
            if k not in cfg["audiences"]:
                raise BuildError(f"Unknown audience {k!r}")
            render(cfg, data, k, as_of, extracted_at, out_dir)
        return 0
    except BuildError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
