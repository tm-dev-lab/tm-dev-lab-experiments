#!/usr/bin/env bash
# Provision an Azure VM, run the final matrix there (jaz on its home turf), pull the results back,
# and tear the VM down. The VM exists ONLY to run the matrix. Everything else is prepared and
# validated locally, so the VM is short-lived and cheap.
#
#   azure-run.sh provision   create RG + VM, install Docker/k6/tooling, copy the experiment, build
#   azure-run.sh start       launch the matrix detached on the VM (survives SSH drops)
#   azure-run.sh status      show progress (cells done + tail of the remote run log)
#   azure-run.sh collect     parse + chart on the VM and pull results back (run after it finishes)
#   azure-run.sh teardown    delete the RG (removes the VM and all of its resources)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${RG:-rg-jaz-experiment}"
LOCATION="${LOCATION:-eastus}"
VM="${VM:-jaz-bench}"
SIZE="${SIZE:-Standard_D4s_v5}"
ADMIN="${ADMIN:-azureuser}"
DIR="jaz-cloud-jvm-tuning"

ip()   { az vm show -g "$RG" -n "$VM" -d --query publicIps -o tsv; }
sshx() { ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 "$ADMIN@$(ip)" "$@"; }
rsy()  { rsync -az -e 'ssh -o StrictHostKeyChecking=accept-new' "$@"; }

provision() {
  echo ">> provisioning $VM ($SIZE) in $RG / $LOCATION"
  az group create -n "$RG" -l "$LOCATION" -o none
  az vm create -g "$RG" -n "$VM" --image Ubuntu2404 --size "$SIZE" \
    --admin-username "$ADMIN" --generate-ssh-keys --public-ip-sku Standard \
    --nic-delete-option Delete --os-disk-delete-option Delete -o none
  echo ">> VM at $(ip); waiting for SSH"
  for i in $(seq 1 40); do sshx 'true' >/dev/null 2>&1 && break; done
  echo ">> installing Docker, k6, and tooling"
  sshx 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl jq rsync python3-matplotlib >/dev/null'
  sshx 'curl -fsSL https://get.docker.com | sudo sh >/dev/null 2>&1 && sudo usermod -aG docker '"$ADMIN"
  sshx 'curl -s https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/k6.gpg && echo "deb [signed-by=/usr/share/keyrings/k6.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list >/dev/null && sudo apt-get update -qq && sudo apt-get install -y -qq k6 >/dev/null'
  echo ">> copying the experiment"
  rsy --delete --exclude 'results/raw/*' --exclude 'results/processed' --exclude 'results/charts' \
      --exclude '**/target' --exclude '.git' "$HERE/" "$ADMIN@$(ip):~/$DIR/"
  echo ">> building the image on the VM"
  sshx "cd ~/$DIR && sg docker -c 'docker build -f docker/Dockerfile -t jaz-exp/digital-bank:21 .'"
  echo ">> provision done"
}

start() {
  echo ">> capturing the VM environment and launching the matrix (detached)"
  sshx "cd ~/$DIR && IMAGE=jaz-exp/digital-bank:21 sg docker -c 'bash scripts/env-capture.sh' > ENVIRONMENT.md"
  # Record what jaz applies on Azure (H5: compare against the local dry-run capture).
  sshx "cd ~/$DIR && sg docker -c 'docker run --rm --memory=1g --cpus=2 --entrypoint sh jaz-exp/digital-bank:21 -c \"JAZ_DRY_RUN=1 jaz -jar /app/app.jar 2>&1\"' > results/jaz-dryrun-azure-1g2cpu.txt 2>&1 || true"
  sshx "cd ~/$DIR && rm -rf results/raw/* results/processed results/charts results/LATEST 2>/dev/null; nohup sg docker -c 'bash scripts/run-azure.sh' > run.log 2>&1 < /dev/null & echo launched"
  echo ">> running. Watch with '$0 status'; when run.log shows DONE, run '$0 collect'"
}

status() {
  sshx "cd ~/$DIR && echo \"cells done: \$(grep -c '^  \\[' run.log 2>/dev/null || echo 0)\"; tail -n 6 run.log 2>/dev/null"
}

collect() {
  echo ">> parse + chart on the VM, then pull everything back"
  sshx "cd ~/$DIR && python3 scripts/parse.py && python3 scripts/charts.py"
  rsy "$ADMIN@$(ip):~/$DIR/results/" "$HERE/results/"
  rsy "$ADMIN@$(ip):~/$DIR/ENVIRONMENT.md" "$HERE/ENVIRONMENT.md"
  rsy "$ADMIN@$(ip):~/$DIR/run.log" "$HERE/results/azure-run.log"
  echo ">> results in $HERE/results/"
}

teardown() { echo ">> deleting $RG (async)"; az group delete -n "$RG" --yes --no-wait; }

case "${1:-}" in
  provision|start|status|collect|teardown) "$1" ;;
  *) echo "usage: $0 {provision|start|status|collect|teardown}"; exit 1 ;;
esac
