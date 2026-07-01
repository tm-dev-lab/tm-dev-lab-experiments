# TM Dev Lab, Experiments

Reproducible experiments for [TM Dev Lab](https://www.tmdevlab.com). Each experiment is a
self-contained subdirectory with its own workload, run harness, raw and processed results, and a
README stating the hypotheses and method. Final write-ups are published on tmdevlab.com and link
back to the experiment here.

## Experiments

| Experiment | Question | Status |
|---|---|---|
| [jaz-cloud-jvm-tuning](jaz-cloud-jvm-tuning/) | Does Microsoft's `jaz` (Azure Command Launcher for Java) beat plain `java` defaults for an I/O- and memory-bound service, with no manual tuning? | complete ([write-up](https://www.tmdevlab.com/jaz-cloud-jvm-defaults.html)) |

## Conventions

- One directory per experiment. Everything needed to reproduce lives inside it.
- Pin versions and record the test-bench (`ENVIRONMENT.md`).
- Commit raw and processed results and the chart-generating scripts.
- All content in English.
