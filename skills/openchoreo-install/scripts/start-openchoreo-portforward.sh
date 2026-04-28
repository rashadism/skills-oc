#!/bin/bash
# Keep OpenChoreo port-forwards alive for Chrome access on Colima
# Run this in a terminal: bash start-openchoreo-portforward.sh

trap "echo 'Stopping...'; kill 0; exit" SIGINT SIGTERM

run_portforward() {
  local ns=$1 svc=$2 port=$3 label=$4
  while true; do
    echo "[$(date +%T)] Starting $label port-forward ($port)..."
    kubectl port-forward -n "$ns" "svc/$svc" "$port:$port" &>/tmp/pf-$svc.log
    echo "[$(date +%T)] $label port-forward died, restarting in 2s..."
    sleep 2
  done
}

echo "=== OpenChoreo Port-Forwards ==="
echo "  Console/API/Thunder → http://openchoreo.localhost:8080"
echo "  Data plane          → http://openchoreoapis.openchoreo.localhost:19080"
echo "  Observability       → http://observer.openchoreo.localhost:9080"
echo ""
echo "Press Ctrl+C to stop."
echo ""

run_portforward openchoreo-control-plane      gateway-default 8080  "Control plane" &
run_portforward openchoreo-data-plane         gateway-default 19080 "Data plane" &
run_portforward openchoreo-observability-plane gateway-default 9080  "Observability" &

wait
