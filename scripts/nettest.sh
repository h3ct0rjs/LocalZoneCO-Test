#!/usr/bin/env bash
# Latency and throughput test against the instance, from a macOS or Linux host.
#
# Usage:   ./scripts/nettest.sh <server-ip>
# Example: ./scripts/nettest.sh "$(terraform output -raw public_ip)"
#
# Requires: ping, curl, traceroute. iperf3 is optional (skipped if missing).
set -uo pipefail

IP="${1:?usage: $0 <server-ip>}"

echo "== ping server (100 packets, 0.2 s apart)"
ping -c 100 -i 0.2 -q "$IP" | tail -2

echo "== TCP connect time to nginx, 20 samples (ms)"
for _ in $(seq 1 20); do
  curl -s -o /dev/null -m 5 -w '%{time_connect}\n' "http://$IP"
done | awk '{v=$1*1000; s+=v; if(min==""||v<min)min=v; if(v>max)max=v}
            END{printf "min %.1f avg %.1f max %.1f\n", min, s/NR, max}'

echo "== traceroute"
traceroute -n -q 2 -w 2 -m 20 "$IP" 2>&1

if command -v iperf3 >/dev/null 2>&1; then
  echo "== iperf3 upload (client -> server)"
  iperf3 -c "$IP" -t 10 | tail -4
  echo "== iperf3 download (server -> client)"
  iperf3 -c "$IP" -t 10 -R | tail -4
  echo "== iperf3 UDP 50 Mbit/s (jitter and loss)"
  iperf3 -c "$IP" -u -b 50M -t 10 | tail -4
else
  echo "iperf3 not installed, skipping throughput tests"
fi
