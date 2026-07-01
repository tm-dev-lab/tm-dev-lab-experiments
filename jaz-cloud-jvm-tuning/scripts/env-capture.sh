#!/usr/bin/env bash
# Capture the test-bench metadata that reproducibility depends on. Prints to stdout; the caller
# redirects it into ENVIRONMENT.md (or a per-run results file).
set -uo pipefail
IMAGE="${IMAGE:-jaz-exp/digital-bank:21}"

echo "# Test-bench environment"
echo
echo "- captured: $(date -u +%FT%TZ)"
echo "- kernel: $(uname -srmo)"
if [ -r /etc/os-release ]; then . /etc/os-release; echo "- os: ${PRETTY_NAME:-unknown}"; fi
echo "- cpu: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
echo "- vcpus: $(nproc)"
echo "- memory: $(free -h 2>/dev/null | awk '/Mem/{print $2}')"
echo "- cgroup: $(stat -fc %T /sys/fs/cgroup 2>/dev/null)"
echo "- docker: $(docker --version 2>/dev/null)"
echo "- image: $IMAGE"
echo "- image_id: $(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null)"
echo "- jaz_version: $(docker run --rm --entrypoint sh "$IMAGE" -c 'JAZ_PRINT_VERSION=1 jaz' 2>/dev/null)"
echo "- jdk: $(docker run --rm --entrypoint java "$IMAGE" -version 2>&1 | head -1)"
if command -v az >/dev/null 2>&1; then
  echo "- azure_vm: $(curl -s -H Metadata:true --max-time 2 'http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01&format=json' 2>/dev/null | jq -r '"\(.vmSize) in \(.location)"' 2>/dev/null || echo 'n/a (not on an Azure VM)')"
fi
echo "- k6: $(k6 version 2>/dev/null | head -1)"
