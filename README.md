# LocalZoneCO-Test

Terraform code and network tests for the AWS Local Zone in Bogotá, Colombia
(`us-east-1-bog-1a`), which became generally available in November 2026.

The code launches one EC2 instance in the Local Zone with nginx and an iperf3
server. The tests measure latency and throughput to it from two clients in
Bogotá: a laptop on Wi-Fi and a Talos Linux Kubernetes cluster on Ethernet.

## Results

Measured on 2026-11-23 from a residential internet connection in Bogotá.
Two runs per client: the first by hand, the second with the scripts in
`scripts/`. Each run sends 100 ICMP pings, 0.2 s apart.

### Latency

| Measurement | Talos run 1 | Talos run 2 | Mac run 1 | Mac run 2 |
|---|---|---|---|---|
| Ping min | 15.1 ms | 14.0 ms | 18.3 ms | 19.5 ms |
| Ping avg | 26.5 ms | 23.1 ms | 37.2 ms | 37.2 ms |
| Ping max | 112.5 ms | 50.9 ms | 184.0 ms | 160.6 ms |
| Packet loss | 0% | 0% | 0% | 0% |
| TCP connect min | 20.2 ms | 18.5 ms | 22.6 ms | 19.3 ms |
| TCP connect avg | 27.8 ms | 80.2 ms | 39.5 ms | 29.0 ms |
| TCP connect max | 61.7 ms | 1052.3 ms | 84.3 ms | 35.8 ms |

The Talos cluster is on Ethernet and the Mac is on Wi-Fi. The 1052 ms
maximum in Talos run 2 is a single sample that took about one second, which
matches one retransmitted TCP SYN; it pulls that run's average up to 80 ms.

### Throughput (iperf3, TCP)

| Direction | Talos run 1 (5 s) | Talos run 2 (5 s) | Mac run 2 (10 s) |
|---|---|---|---|
| Upload (client to server) | 33 Mbit/s | 5 Mbit/s | 25 Mbit/s |
| Upload retransmissions | 14 | 206 | 1456 |
| Download (server to client) | 31 Mbit/s | 376 Mbit/s | 20 Mbit/s |
| Download retransmissions | 1 | 572 | 80 |

UDP from the Mac at a 50 Mbit/s target (10 s): 40.4 Mbit/s received,
0.9 ms jitter, 18% packet loss.

Throughput varied a lot between runs on the same line: download from the
cluster went from 31 to 376 Mbit/s, and upload from 33 down to 5 Mbit/s.
The retransmission counts and the UDP loss point to packet loss on the
uplink of the residential connection. Treat these throughput figures as a
description of that connection, not of the instance.

### Where the latency comes from

Traceroute from the cluster (addresses generalised):

| Hop | What it is | Latency |
|---|---|---|
| Home router | LAN | ~0.3 ms |
| ISP modem | LAN | ~2 ms |
| First hop inside the ISP | Access line | ~13–20 ms |
| Amazon network | Peering in Colombia | ~22–31 ms |

- The target was under 10 ms. It was not reached: the best case was 15 ms.
- The access line between the modem and the ISP adds 11–18 ms on its own.
  That is the floor on this connection, and it is outside AWS.
- From the ISP's first hop to Amazon's network adds only a few milliseconds,
  and the route stays inside the country.
- Wi-Fi added about 10 ms to the average, plus jitter, compared with Ethernet.

These numbers describe one residential connection. They are not a benchmark
of the Local Zone itself; measure from where your own users are.

## What the Terraform code creates

- One EC2 instance (`c7i.large` by default) with Amazon Linux 2023, IMDSv2
  required and an encrypted gp3 root volume.
- A user-data script that installs nginx with a page showing the instance
  metadata, and runs iperf3 as a systemd service on port 5201.
- An IAM role and instance profile for Session Manager. There is no SSH key
  and port 22 is closed.
- A security group that allows HTTP and ICMP echo in from anywhere, and
  iperf3 (5201 TCP/UDP) only from the public IP of whoever runs Terraform.

The code does not create the network. It expects:

- The Local Zone group `us-east-1-bog-1` to be opted in.
- A subnet in `us-east-1-bog-1a` inside the default VPC, routed to an
  internet gateway.

The plan fails with a clear message if the zone is not available or not
opted in.

## Notes on the Bogotá Local Zone

- It is managed from its parent region, `us-east-1`.
- Instance families offered at launch: C7i, M7i and R7i. There are no
  burstable types.
- EBS volume types: gp3, gp2 and io1.
- Public IPv4 addresses come from the `us-east-1-bog-1` network border group.
- EKS worker nodes can run in the zone, but the control plane stays in the
  parent region and its subnets must be in regular availability zones.

## Usage

Requirements: Terraform 1.5 or later, AWS CLI v2, the Session Manager plugin,
and AWS credentials with EC2, IAM and SSM permissions.

```bash
# Opt in to the Local Zone (once per account)
aws ec2 modify-availability-zone-group --region us-east-1 \
  --group-name us-east-1-bog-1 --opt-in-status opted-in

# Create a subnet in the zone if you don't have one (adjust VPC and CIDR)
aws ec2 create-subnet --region us-east-1 --vpc-id <vpc-id> \
  --cidr-block 172.31.96.0/20 --availability-zone us-east-1-bog-1a

# Launch
terraform init
terraform apply
```

Useful outputs after the apply:

```bash
terraform output web_url                 # nginx page with the metadata
terraform output network_test_commands   # ping and iperf3 commands
$(terraform output -raw ssm_connect_command)   # shell via Session Manager
```

### Variables

| Variable | Default | Purpose |
|---|---|---|
| `instance_type` | `c7i.large` | Must be a c7i, m7i or r7i type |
| `http_ingress_cidrs` | `["0.0.0.0/0"]` | Who can open the nginx page |
| `icmp_ingress_cidrs` | `["0.0.0.0/0"]` | Who can ping the instance |
| `iperf3_ingress_cidrs` | `[]` | Who can use iperf3; empty means your own public IP |
| `root_volume_size_gb` | `30` | Root volume size |

iperf3 is restricted by default because an open iperf3 server lets anyone
generate outbound traffic that the account owner pays for.

## Running the tests

From a macOS or Linux host:

```bash
./scripts/nettest.sh "$(terraform output -raw public_ip)"
```

From a Kubernetes cluster, using a temporary `nicolaka/netshoot` pod that
deletes itself:

```bash
./scripts/nettest-k8s.sh "$(terraform output -raw public_ip)"
```

Both scripts run 100 pings, 20 TCP connect samples against nginx, a
traceroute and iperf3 upload and download runs.

## Cost and cleanup

The instance and its public IPv4 address are billed by the hour, and outbound
data transfer is billed per GB. Destroy everything when you finish:

```bash
terraform destroy
```

## References

- [Announcing the general availability of a new AWS Local Zone in Bogotá, Colombia](https://aws.amazon.com/about-aws/whats-new/2026/11/aws-local-zone-bogota-colombia/)
- [Launch low-latency EKS clusters with AWS Local Zones](https://docs.aws.amazon.com/eks/latest/userguide/local-zones.html)
