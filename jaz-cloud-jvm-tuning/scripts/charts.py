#!/usr/bin/env python3
"""Grouped java-vs-jaz bar charts per (memory, cpu) cell, from results/processed/summary.json.

Usage: charts.py   ->   writes results/charts/*.png
"""
import json
import sys
from pathlib import Path

EXP = Path(__file__).resolve().parents[1]
JAVA_COLOR = "#8a8f98"   # neutral grey
JAZ_COLOR = "#9d5cff"    # TM Dev Lab violet


def cell_order(cells):
    def key(c):
        mem, cpu = c
        gb = int(mem[:-1]) if mem[-1] == "g" else int(mem[:-1]) / 1024
        return (gb, int(cpu))
    return sorted(cells, key=key)


def main():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        sys.exit("matplotlib not installed. Run:  pip install matplotlib")

    summ_path = EXP / "results" / "processed" / "summary.json"
    summ = json.loads(summ_path.read_text()) if summ_path.exists() else []
    if not summ:
        sys.exit("no summary data; run parse.py first")

    cells = cell_order({(s["mem"], s["cpu"]) for s in summ})
    labels = [f"{m}/{c}cpu" for m, c in cells]

    def series(launcher, field):
        by = {(s["mem"], s["cpu"]): s.get(field) for s in summ if s["launcher"] == launcher}
        return [by.get(c) or 0 for c in cells]

    charts = [
        ("throughput_rps", "Throughput (req/s) — higher is better", "throughput.png"),
        ("lat_p99_ms", "p99 latency (ms) — lower is better", "latency_p99.png"),
        ("mem_idle_mb", "Idle memory at the limit (MB) — lower = less waste", "idle_memory.png"),
        ("gc_total_pause_ms", "Total GC pause (ms) — lower is better", "gc_pause.png"),
    ]

    outdir = EXP / "results" / "charts"
    outdir.mkdir(parents=True, exist_ok=True)
    x = list(range(len(cells)))
    w = 0.38
    for field, title, fname in charts:
        java = series("java", field)
        jaz = series("jaz", field)
        fig, ax = plt.subplots(figsize=(8, 4.5))
        ax.bar([i - w / 2 for i in x], java, width=w, label="java", color=JAVA_COLOR)
        ax.bar([i + w / 2 for i in x], jaz, width=w, label="jaz", color=JAZ_COLOR)
        ax.set_xticks(x)
        ax.set_xticklabels(labels)
        ax.set_title(title)
        ax.legend()
        ax.grid(axis="y", alpha=0.3)
        fig.tight_layout()
        fig.savefig(outdir / fname, dpi=120)
        plt.close(fig)
        print("wrote", outdir / fname)


if __name__ == "__main__":
    main()
