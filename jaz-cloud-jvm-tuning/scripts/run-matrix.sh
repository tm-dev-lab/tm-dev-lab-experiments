#!/usr/bin/env bash
# Run the java-vs-jaz matrix. For each container memory limit x vCPU limit x launcher x repetition,
# start the digital-bank under cgroup limits with GC logging, wait until the warm set is loaded,
# warm up, drive load with k6, then collect throughput/latency/memory/GC/startup into
# results/raw/<stamp>/. Everything is overridable via environment so the local dry-run and the full
# Azure run share code. The memory x cpu grid deliberately straddles the JVM's "server-class"
# ergonomic boundary (G1 default needs >=2 vCPU AND >=1792MB, else Serial GC).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-jaz-exp/digital-bank:21}"
PORT="${PORT:-18080}"
CNAME="${CNAME:-bank-run}"

MEMS="${MEMS:-1g 2g}"
CPUS="${CPUS:-1 2}"
LAUNCHERS="${LAUNCHERS:-java jaz}"
RUNS="${RUNS:-5}"
WARMUP="${WARMUP:-30s}"
MEASURE="${MEASURE:-60s}"
VUS="${VUS:-100}"
PRELOAD_ACCOUNTS="${PRELOAD_ACCOUNTS:-100000}"
PRELOAD_TX="${PRELOAD_TX:-4}"
IO_DELAY="${IO_DELAY:-5}"
STMT_LIMIT="${STMT_LIMIT:-50}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAW="$HERE/results/raw/$STAMP"
mkdir -p "$RAW"

# GC logging is measurement-only. -Xlog is NOT a jaz tuning flag, so jaz still applies its tuning.
GC_ARGS='-Xlog:gc*,gc+init=info:file=/logs/gc.log:time,uptime,level,tags'

echo "run-matrix $STAMP"
echo "  mems=[$MEMS] cpus=[$CPUS] launchers=[$LAUNCHERS] runs=$RUNS"
echo "  vus=$VUS warmup=$WARMUP measure=$MEASURE preload=${PRELOAD_ACCOUNTS}x${PRELOAD_TX} io=${IO_DELAY}ms"
echo "  out=$RAW"

cleanup() { docker rm -f "$CNAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# --- Record the exact flags each launcher applies per (mem,cpu) cell (transparency, H5) ---
for mem in $MEMS; do
  for cpu in $CPUS; do
    fdir="$RAW/_flags/mem${mem}_cpu${cpu}"; mkdir -p "$fdir"
    docker run --rm --memory="$mem" --memory-swap="$mem" --cpus="$cpu" --entrypoint sh "$IMAGE" \
      -c 'JAZ_DRY_RUN=1 jaz -jar /app/app.jar 2>&1' > "$fdir/jaz-dryrun.txt" 2>&1 || true
    docker run --rm --memory="$mem" --memory-swap="$mem" --cpus="$cpu" --entrypoint sh "$IMAGE" \
      -c 'java -XX:+PrintFlagsFinal -version 2>/dev/null | grep -E "MaxHeapSize|InitialHeapSize|MaxRAMPercentage|UseG1GC|UseParallelGC|UseSerialGC|UseZGC|UseShenandoahGC|ActiveProcessorCount" | tr -s " "' \
      > "$fdir/java-defaults.txt" 2>&1 || true
  done
done

# --- Main matrix ---
for mem in $MEMS; do
  for cpu in $CPUS; do
    for launcher in $LAUNCHERS; do
      for run in $(seq 1 "$RUNS"); do
        cell="mem${mem}_cpu${cpu}/${launcher}/run${run}"
        outdir="$RAW/$cell"; mkdir -p "$outdir"
        cleanup

        if ! docker run -d --name "$CNAME" \
          --memory="$mem" --memory-swap="$mem" --cpus="$cpu" \
          -e LAUNCHER="$launcher" -e JAVA_ARGS="$GC_ARGS" \
          -e BANK_PRELOAD_ACCOUNTS="$PRELOAD_ACCOUNTS" -e BANK_PRELOAD_TX="$PRELOAD_TX" \
          -e BANK_IO_DELAY_MS="$IO_DELAY" \
          -v "$outdir:/logs" -p "$PORT:8080" "$IMAGE" > "$outdir/run.txt" 2>&1; then
          echo "  [$cell] docker run FAILED: $(tail -n1 "$outdir/run.txt")"
          cleanup; continue
        fi

        # Readiness: poll Spring's readiness probe, which flips to UP only after the preload
        # ApplicationRunner finishes. curl does the waiting internally (retries through connection
        # refused and 503s), so this neither busy-loops nor hangs following the log stream.
        if ! curl --retry-connrefused --retry-all-errors --retry 200 --retry-delay 1 --retry-max-time 200 \
               -sf -o /dev/null "http://localhost:$PORT/actuator/health/readiness"; then
          echo "  [$cell] NOT READY (readiness never came up, likely OOM at this limit)"
          docker logs "$CNAME" > "$outdir/app.log" 2>&1 || true
          docker inspect -f 'status={{.State.Status}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' "$CNAME" > "$outdir/state.txt" 2>&1 || true
          cleanup; continue
        fi

        # Warmup (discarded).
        BASE_URL="http://localhost:$PORT" PRELOAD_ACCOUNTS="$PRELOAD_ACCOUNTS" STATEMENT_LIMIT="$STMT_LIMIT" \
          VUS="$VUS" DURATION="$WARMUP" SUMMARY_OUT="$outdir/warmup.json" \
          k6 run --quiet "$HERE/scripts/load.js" >/dev/null 2>&1 || true

        # Measurement.
        BASE_URL="http://localhost:$PORT" PRELOAD_ACCOUNTS="$PRELOAD_ACCOUNTS" STATEMENT_LIMIT="$STMT_LIMIT" \
          VUS="$VUS" DURATION="$MEASURE" SUMMARY_OUT="$outdir/k6.json" \
          k6 run --quiet "$HERE/scripts/load.js" > "$outdir/k6.txt" 2>&1 || true

        # Resource footprint (cgroup v2), startup log, and container state.
        docker exec "$CNAME" sh -c 'for f in memory.peak memory.current memory.max cpu.stat; do echo "== $f =="; cat /sys/fs/cgroup/$f 2>/dev/null; done' > "$outdir/cgroup.txt" 2>&1 || true
        docker inspect -f 'status={{.State.Status}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}}' "$CNAME" > "$outdir/state.txt" 2>&1 || true
        docker logs "$CNAME" > "$outdir/app.log" 2>&1 || true
        echo "mem=$mem cpu=$cpu launcher=$launcher run=$run" > "$outdir/cell.txt"

        printf "  [%s] %s\n" "$cell" "$(tail -n1 "$outdir/k6.txt" 2>/dev/null)"
        cleanup
      done
    done
  done
done

echo "DONE -> $RAW"
echo "$RAW" > "$HERE/results/LATEST"
