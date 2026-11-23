#!/usr/bin/env bash
# Runs the same test from inside a Kubernetes cluster, using a temporary
# nicolaka/netshoot pod that deletes itself when it finishes.
#
# Usage:   ./scripts/nettest-k8s.sh <server-ip> [kube-context]
# Example: ./scripts/nettest-k8s.sh "$(terraform output -raw public_ip)"
#
# Note: the iperf3 port is only open to the CIDRs in var.iperf3_ingress_cidrs.
# The cluster must leave through one of those public IPs for iperf3 to work.
set -euo pipefail

IP="${1:?usage: $0 <server-ip> [kube-context]}"
CONTEXT="${2:-$(kubectl config current-context)}"

kubectl --context "$CONTEXT" run nettest-bog \
  --rm -i --restart=Never --quiet \
  --image=nicolaka/netshoot \
  --pod-running-timeout=3m \
  --env="IP=$IP" -- sh -c '
echo "== ping server (100 packets, 0.2 s apart)"
ping -c 100 -i 0.2 -q "$IP" | tail -2

echo "== TCP connect time to nginx, 20 samples (ms)"
for i in $(seq 1 20); do
  curl -s -o /dev/null -m 5 -w "%{time_connect}\n" "http://$IP"
done | awk "{v=\$1*1000; s+=v; if(min==\"\"||v<min)min=v; if(v>max)max=v}
            END{printf \"min %.1f avg %.1f max %.1f\n\", min, s/NR, max}"

echo "== traceroute"
traceroute -n -q 2 -w 2 -m 12 "$IP" 2>&1

echo "== iperf3 upload (client -> server)"
iperf3 -c "$IP" -t 5 2>&1 | tail -4
echo "== iperf3 download (server -> client)"
iperf3 -c "$IP" -t 5 -R 2>&1 | tail -4
'
