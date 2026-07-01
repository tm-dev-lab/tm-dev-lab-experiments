#!/usr/bin/env python3
"""Parse a results/raw/<stamp>/ tree into per-run and summary CSV/JSON.

The summary carries the per-cell median of each metric plus, for the three headline metrics
(throughput, p99, GC pause), the run-to-run spread as min, max, and coefficient of variation.

Usage: parse.py [RAW_DIR]   (defaults to the dir in results/LATEST, else the newest raw dir)
"""
import csv
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

EXP = Path(__file__).resolve().parents[1]


def raw_dir():
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    latest = EXP / "results" / "LATEST"
    if latest.exists():
        p = Path(latest.read_text().strip())
        if not p.is_absolute():
            p = EXP / p
        if p.exists():
            return p
        # LATEST can hold the path from the machine that produced the run (e.g. the Azure VM),
        # which does not exist here. Fall back to the newest local raw dir.
    dirs = sorted((EXP / "results" / "raw").glob("*"))
    return dirs[-1] if dirs else None


def read(p):
    try:
        return Path(p).read_text()
    except OSError:
        return ""


def parse_k6(p):
    txt = read(p)
    if not txt:
        return {}
    try:
        m = json.loads(txt)["metrics"]
        d = m["http_req_duration"]["values"]
        return {
            "throughput_rps": round(m["http_reqs"]["values"]["rate"], 2),
            "reqs": m["http_reqs"]["values"]["count"],
            "lat_avg_ms": round(d.get("avg", 0), 3),
            "lat_p50_ms": round(d.get("med", 0), 3),
            "lat_p90_ms": round(d.get("p(90)", 0), 3),
            "lat_p95_ms": round(d.get("p(95)", 0), 3),
            "lat_p99_ms": round(d.get("p(99)", 0), 3),
            "lat_max_ms": round(d.get("max", 0), 3),
            "err_rate": round(m.get("server_errors", {}).get("values", {}).get("rate", 0), 5),
        }
    except (KeyError, ValueError):
        return {}


def parse_cgroup(p):
    txt = read(p)
    out = {}
    parts = re.split(r"== (\S+) ==", txt)
    for i in range(1, len(parts) - 1, 2):
        key, val = parts[i].strip(), parts[i + 1].strip()
        if key in ("memory.peak", "memory.current", "memory.max"):
            try:
                out[key] = int(val.splitlines()[0])
            except (ValueError, IndexError):
                pass
        elif key == "cpu.stat":
            mm = re.search(r"usage_usec\s+(\d+)", val)
            if mm:
                out["cpu_usage_usec"] = int(mm.group(1))
    return out


def parse_gc(p):
    txt = read(p)
    out = {"gc_type": None, "gc_count": 0, "gc_total_pause_ms": 0.0, "gc_max_pause_ms": 0.0}
    um = re.search(r"Using (\w+)", txt)
    if um:
        out["gc_type"] = um.group(1)
    pauses = [float(x) for x in re.findall(r" Pause [^\n]*?([0-9]+\.[0-9]+)ms", txt)]
    if pauses:
        out["gc_count"] = len(pauses)
        out["gc_total_pause_ms"] = round(sum(pauses), 2)
        out["gc_max_pause_ms"] = round(max(pauses), 2)
    return out


def parse_startup(p):
    m = re.search(r"Started BankApplication in ([0-9.]+) seconds", read(p))
    return {"startup_s": float(m.group(1))} if m else {}


def limit_bytes(mem):
    v, u = int(mem[:-1]), mem[-1].lower()
    return v * (1024 ** 2 if u == "m" else 1024 ** 3)


def cell_meta_from_path(d):
    parts = d.parts
    memcpu = next(x for x in parts if x.startswith("mem") and "_cpu" in x)
    return {
        "mem": memcpu.split("_")[0][3:],
        "cpu": memcpu.split("cpu")[1],
        "launcher": parts[-2],
        "run": int(parts[-1].replace("run", "")),
    }


def main():
    rd = raw_dir()
    if not rd or not rd.exists():
        sys.exit("no raw results dir found")

    rows = []
    seen = set()
    for cellf in rd.rglob("cell.txt"):
        d = cellf.parent
        seen.add(d)
        row = dict(kv.split("=") for kv in cellf.read_text().split())
        row["run"] = int(row["run"])
        row.update(parse_k6(d / "k6.json"))
        cg = parse_cgroup(d / "cgroup.txt")
        row.update(cg)
        row.update(parse_gc(d / "gc.log"))
        row.update(parse_startup(d / "app.log"))
        row["oom"] = "oom=true" in read(d / "state.txt")
        lim = limit_bytes(row["mem"])
        row["mem_limit_b"] = lim
        if "memory.peak" in cg:
            row["mem_peak_b"] = cg["memory.peak"]
            row["mem_idle_b"] = lim - cg["memory.peak"]
            row["mem_util_pct"] = round(100 * cg["memory.peak"] / lim, 1)
        rows.append(row)

    # Cells that never became ready (e.g. OOM during preload) have state.txt but no cell.txt.
    for statef in rd.rglob("state.txt"):
        d = statef.parent
        if d in seen:
            continue
        try:
            row = cell_meta_from_path(d)
        except StopIteration:
            continue
        row["oom"] = "oom=true" in read(statef)
        row["not_ready"] = True
        rows.append(row)

    proc = EXP / "results" / "processed"
    proc.mkdir(parents=True, exist_ok=True)
    cols = ["mem", "cpu", "launcher", "run", "throughput_rps", "lat_avg_ms", "lat_p50_ms",
            "lat_p90_ms", "lat_p95_ms", "lat_p99_ms", "lat_max_ms", "err_rate", "mem_peak_b",
            "mem_limit_b", "mem_idle_b", "mem_util_pct", "cpu_usage_usec", "gc_type", "gc_count",
            "gc_total_pause_ms", "gc_max_pause_ms", "startup_s", "oom", "not_ready"]
    with open(proc / "runs.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in sorted(rows, key=lambda r: (r["mem"], r["launcher"], r["run"])):
            w.writerow(r)

    def med(vals):
        vals = [v for v in vals if isinstance(v, (int, float)) and not isinstance(v, bool)]
        return round(statistics.median(vals), 2) if vals else None

    def spread(vals):
        # Run-to-run dispersion for a metric across the N runs of a cell: min, max, and the
        # coefficient of variation (sample stdev / mean, in percent) as a scale-free spread.
        vals = [v for v in vals if isinstance(v, (int, float)) and not isinstance(v, bool)]
        if not vals:
            return None, None, None
        mn, mx = round(min(vals), 2), round(max(vals), 2)
        cv = round(statistics.stdev(vals) / statistics.mean(vals) * 100, 1) if len(vals) > 1 and statistics.mean(vals) else 0.0
        return mn, mx, cv

    groups = defaultdict(list)
    for r in rows:
        groups[(r["mem"], r.get("cpu", "?"), r["launcher"])].append(r)
    summ = []
    for (mem, cpu, launcher), rs in sorted(groups.items(), key=lambda kv: (limit_bytes(kv[0][0]), kv[0][1], kv[0][2])):
        thr = [r.get("throughput_rps") for r in rs]
        p99 = [r.get("lat_p99_ms") for r in rs]
        gcp = [r.get("gc_total_pause_ms") for r in rs]
        thr_min, thr_max, thr_cv = spread(thr)
        p99_min, p99_max, p99_cv = spread(p99)
        gcp_min, gcp_max, gcp_cv = spread(gcp)
        summ.append({
            "mem": mem, "cpu": cpu, "launcher": launcher, "n": len(rs),
            "throughput_rps": med(thr),
            "throughput_rps_min": thr_min, "throughput_rps_max": thr_max, "throughput_rps_cv_pct": thr_cv,
            "lat_avg_ms": med([r.get("lat_avg_ms") for r in rs]),
            "lat_p50_ms": med([r.get("lat_p50_ms") for r in rs]),
            "lat_p90_ms": med([r.get("lat_p90_ms") for r in rs]),
            "lat_p95_ms": med([r.get("lat_p95_ms") for r in rs]),
            "lat_p99_ms": med(p99),
            "lat_p99_ms_min": p99_min, "lat_p99_ms_max": p99_max, "lat_p99_ms_cv_pct": p99_cv,
            "mem_peak_mb": med([r["mem_peak_b"] / 1048576 for r in rs if r.get("mem_peak_b")]),
            "mem_idle_mb": med([r["mem_idle_b"] / 1048576 for r in rs if r.get("mem_idle_b")]),
            "mem_util_pct": med([r.get("mem_util_pct") for r in rs]),
            "gc_type": next((r.get("gc_type") for r in rs if r.get("gc_type")), None),
            "gc_total_pause_ms": med(gcp),
            "gc_total_pause_ms_min": gcp_min, "gc_total_pause_ms_max": gcp_max, "gc_total_pause_ms_cv_pct": gcp_cv,
            "startup_s": med([r.get("startup_s") for r in rs]),
            "oom_runs": sum(1 for r in rs if r.get("oom")),
            "not_ready_runs": sum(1 for r in rs if r.get("not_ready")),
        })
    if summ:
        with open(proc / "summary.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(summ[0].keys()))
            w.writeheader()
            w.writerows(summ)
    (proc / "summary.json").write_text(json.dumps(summ, indent=2))

    print(f"parsed {len(rows)} runs from {rd}")
    for s in summ:
        print(f"  {s['mem']:>3}/{s['cpu']}cpu {s['launcher']:>4} n={s['n']} | thr={s['throughput_rps']}/s "
              f"p99={s['lat_p99_ms']}ms peak={s['mem_peak_mb']}MB idle={s['mem_idle_mb']}MB "
              f"gc={s['gc_type']}/{s['gc_total_pause_ms']}ms start={s['startup_s']}s "
              f"oom={s['oom_runs']} notready={s['not_ready_runs']}")


if __name__ == "__main__":
    main()
