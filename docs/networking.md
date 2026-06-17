# Networking

This document covers all network layers in the cluster: the physical LAN, the podman container network fabric on the host, k3s cluster networking, ingress, DNS, and firewall configuration.

---

## Diagram Key

The following key applies to all diagrams in this document.

| Symbol | Meaning |
|---|---|
| Rectangle | Script / process / service |
| Rounded rectangle | Config data / address |
| Cylinder | Persistent storage / config |
| Diamond | Decision |
| Circle | Endpoint (client / external) |
| 🔵 Blue | Host, server, or active process |
| 🟢 Green | Storage, secret, or persistent service |
| 🟡 Amber | Decision or intermediate routing |
| 🟣 Purple | Container image / external tool |
| 🩵 Teal | Network / config data |
| 🔴 Red | Restricted or internal-only |

---

## Network Layers Overview

| Layer | Technology | Subnet / Range |
|-------|-----------|----------------|
| Physical LAN | NetworkManager · eno1 | 10.50.0.0/24 |
| Container — server plane | podman bridge `k3s-server` | 10.10.0.0/16 |
| Container — agent plane | podman bridge `k3s-agent` | 10.11.0.0/16 |
| Container — service plane | podman bridge `k3s-service` | 10.43.0.0/16 |
| Container — ingress plane | podman macvlan `k3s-ingress` | 10.50.0.0/24 (shared with LAN) |
| Kubernetes pod network | k3s (default CIDR) | 10.42.0.0/16 |
| Kubernetes service CIDR | k3s | 10.43.0.0/16 |
| Cluster/pod route | static via 10.50.0.11 | 10.16.0.0/16 |

---

## Physical Network

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    INET(["fa:fa-cloud Internet"])

    subgraph LAN["Physical LAN — 10.50.0.0/24"]
        GW["fa:fa-network-wired expresso.lan\n10.50.0.1\nGateway · DNS upstream"]
        RICK["fa:fa-server rick.expresso.lan\neno1 · 10.50.0.2/24\nMAC D8:BB:C1:09:C6:4C · MTU 1500"]
        RPI["fa:fa-microchip rpi4-0\n10.50.0.11"]
        R10["fa:fa-server r10.expresso.lan\n10.50.0.100"]
        THINKPAD["fa:fa-server rh-thinkpad-p1\n10.50.0.50"]
    end

    ROUTE["fa:fa-network-wired Static route nexthop\n10.50.0.11\n10.16.0.0/16"]

    INET <-->|"NAT"| GW
    GW <--> RICK
    GW <--> RPI
    GW <--> R10
    GW <--> THINKPAD
    RICK -.->|"route 10.16.0.0/16\nmetric 90"| ROUTE

    style INET fill:#1d4ed8,stroke:#ccc,color:#fff
    style GW fill:#1d4ed8,stroke:#ccc,color:#fff
    style RICK fill:#1d4ed8,stroke:#ccc,color:#fff
    style RPI fill:#1d4ed8,stroke:#ccc,color:#fff
    style R10 fill:#1d4ed8,stroke:#ccc,color:#fff
    style THINKPAD fill:#1d4ed8,stroke:#ccc,color:#fff
    style ROUTE fill:#0f766e,stroke:#ccc,color:#fff
```

The production node `rick.expresso.lan` is the only node running k3s server containers. The RPi4 (`rpi4-0`) runs as an external k3s agent and must route back to the podman container networks on `rick` — the static route `10.16.0.0/16 via 10.50.0.11` facilitates this.

### Host interface — eno1

| Setting | Value |
|---------|-------|
| IP address | 10.50.0.2/24 |
| Gateway | 10.50.0.1 |
| DNS | 10.50.0.1, 8.8.8.8 |
| DNS search | expresso.lan |
| Static route | 10.16.0.0/16 via 10.50.0.11 (metric 90) |
| IPv6 | disabled |
| NftablesFlowtable | eno1 (hardware offload fastpath) |
| GRO / GSO / TSO | enabled |
| Ring buffers | 256 Rx / 256 Tx |

---

## Podman Container Network Fabric

All k3s processes run inside podman containers managed by systemd Quadlet units. Each container attaches to one or more named podman networks. The network backend is **netavark** with **nftables** as the firewall driver.

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart LR
    subgraph NETS["Podman Networks"]
        SRV_NET["fa:fa-network-wired k3s-server\nbridge\n10.10.0.0/16\ngw 10.10.254.254"]
        AGT_NET["fa:fa-network-wired k3s-agent\nbridge\n10.11.0.0/16\ngw 10.11.254.254"]
        SVC_NET["fa:fa-network-wired k3s-service\nbridge\n10.43.0.0/16\ngw 10.43.254.254"]
        ING_NET["fa:fa-network-wired k3s-ingress\nmacvlan → eno1\n10.50.0.0/24\ngw 10.50.0.1"]
    end

    subgraph CONTAINERS["Quadlet Containers"]
        S0["fa:fa-cube k3s-server-0\nserver0=10.10.0.2\nservice0=10.43.2.2\nexternal=10.50.0.2"]
        S1["fa:fa-cube k3s-server-1\nserver0=10.10.0.3\nservice0=10.43.2.3"]
        S2["fa:fa-cube k3s-server-2\nserver0=10.10.0.4\nservice0=10.43.2.4"]
        A0["fa:fa-cube k3s-agent-0\nagent0=10.11.0.6\nservice0=10.43.0.6"]
        SVC0["fa:fa-cube k3s-svclb-0\nagent0=10.11.0.5\nservice0=10.43.0.5\nexternal=10.50.0.24"]
    end

    SRV_NET --- S0
    SRV_NET --- S1
    SRV_NET --- S2
    AGT_NET --- A0
    AGT_NET --- SVC0
    SVC_NET --- S0
    SVC_NET --- S1
    SVC_NET --- S2
    SVC_NET --- A0
    SVC_NET --- SVC0
    ING_NET --- SVC0

    style SRV_NET fill:#0f766e,stroke:#ccc,color:#fff
    style AGT_NET fill:#0f766e,stroke:#ccc,color:#fff
    style SVC_NET fill:#0f766e,stroke:#ccc,color:#fff
    style ING_NET fill:#0f766e,stroke:#ccc,color:#fff
    style S0 fill:#7e22ce,stroke:#ccc,color:#fff
    style S1 fill:#7e22ce,stroke:#ccc,color:#fff
    style S2 fill:#7e22ce,stroke:#ccc,color:#fff
    style A0 fill:#7e22ce,stroke:#ccc,color:#fff
    style SVC0 fill:#7e22ce,stroke:#ccc,color:#fff
```

### Network definitions

| Podman network | Driver | Interface template | Subnet | Gateway |
|---------------|--------|--------------------|--------|---------|
| `k3s-server` | bridge | `server0` | 10.10.0.0/16 | 10.10.254.254 |
| `k3s-agent` | bridge | `agent0` | 10.11.0.0/16 | 10.11.254.254 |
| `k3s-service` | bridge | `service0` | 10.43.0.0/16 | 10.43.254.254 |
| `k3s-ingress` | macvlan | `eno1` | 10.50.0.0/24 | 10.50.0.1 |

The `k3s-ingress` network uses **macvlan** mode attached to `eno1`, giving the ingress container a distinct MAC and a routable IP on the physical LAN. This allows Traefik's LoadBalancer IP (10.50.0.24) to be directly reachable from the LAN without NAT.

### Container network attachments

| Container | server plane | agent plane | service plane | external IP |
|-----------|-------------|-------------|---------------|-------------|
| `k3s-server-0` | 10.10.0.2 | — | 10.43.2.2 | 10.50.0.2 |
| `k3s-server-1` | 10.10.0.3 | — | 10.43.2.3 | — |
| `k3s-server-2` | 10.10.0.4 | — | 10.43.2.4 | — |
| `k3s-agent-0` | — | 10.11.0.6 | 10.43.0.6 | — |
| `k3s-svclb-0` | — | 10.11.0.5 | 10.43.0.5 | 10.50.0.24 |

Container interface names are set explicitly via `interface_name=` in the Quadlet `Network=` directive (e.g. `kube-server.network:ip=10.10.0.2,interface_name=server0`).

---

## k3s Cluster Networking

### Control plane — kube-vip HA VIP

kube-vip runs as a DaemonSet and manages a virtual IP on the `server0` interface of control-plane nodes. Server-1 and server-2 both join the cluster via the VIP, not a specific node's IP.

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    CLIENT(["fa:fa-terminal kubectl / agent join"])

    VIP(("fa:fa-dharmachakra kube-vip VIP\n10.10.0.100:6443\nserver0 interface\nARP-based leader election"))

    S0["fa:fa-cube k3s-server-0\n10.10.0.2:6443\nK3S_CLUSTER_INIT=true\nexternal 10.50.0.2"]
    S1["fa:fa-cube k3s-server-1\n10.10.0.3:6443\nK3S_URL=https://10.10.0.100:6443"]
    S2["fa:fa-cube k3s-server-2\n10.10.0.4:6443\nK3S_URL=https://10.10.0.100:6443"]

    CLIENT -->|"HTTPS 6443"| VIP
    VIP -->|"leader routes to"| S0
    VIP -.->|"failover"| S1
    VIP -.->|"failover"| S2
    S0 -->|"cluster-init\nembeds etcd"| S1
    S0 -->|"cluster-init\nembeds etcd"| S2

    style CLIENT fill:#1d4ed8,stroke:#ccc,color:#fff
    style VIP fill:#15803d,stroke:#ccc,color:#fff
    style S0 fill:#7e22ce,stroke:#ccc,color:#fff
    style S1 fill:#7e22ce,stroke:#ccc,color:#fff
    style S2 fill:#7e22ce,stroke:#ccc,color:#fff
```

**kube-vip configuration (prod):**

| Setting | Value |
|---------|-------|
| VIP address | 10.10.0.100 |
| VIP interface | `server0` (inside the container) |
| Mode | ARP leader election |
| LB port | 6443 |
| LB forward method | local |
| Service LB | disabled (`svc_enable: false`) |
| nftables egress | enabled |

**TLS SANs on k3s server (prod):**
- `10.10.0.1`, `10.10.0.100` (kube-vip VIP)
- `10.50.0.2` (host LAN IP)
- `rick.expresso.lan`, `api.rick.expresso.lan`

### Service startup order

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    S0["fa:fa-cube k3s-server-0\nK3S_CLUSTER_INIT=true"]
    S1["fa:fa-cube k3s-server-1"]
    S2["fa:fa-cube k3s-server-2"]
    A0["fa:fa-cube k3s-agent-0"]
    SVC0["fa:fa-cube k3s-svclb-0"]

    S0 ==>|"Before= / Wants="| S1
    S0 ==>|"Before= / Wants="| S2
    S0 ==>|"Before= / Wants="| A0
    S0 ==>|"Before= / Wants="| SVC0
    S1 -.->|"Wants="| S2

    style S0 fill:#15803d,stroke:#ccc,color:#fff
    style S1 fill:#7e22ce,stroke:#ccc,color:#fff
    style S2 fill:#7e22ce,stroke:#ccc,color:#fff
    style A0 fill:#7e22ce,stroke:#ccc,color:#fff
    style SVC0 fill:#7e22ce,stroke:#ccc,color:#fff
```

---

## Ingress — Traefik

Traefik runs on the `k3s-svclb-0` node (the dedicated ingress / service LB node) and is exposed via a `LoadBalancer` service on the macvlan ingress network.

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    EXT(["fa:fa-network-wired LAN Client\n10.50.0.0/24"])

    LB["fa:fa-route Traefik LoadBalancer\n10.50.0.24\nHTTP :80 · HTTPS :443"]

    subgraph INTERNAL["Internal ClusterIP only"]
        INT_SVC["fa:fa-shield-halved Traefik Internal\nAllowed: 10.10–11.0.0/16\n10.16.0.0/16 · 10.43.0.0/16"]
    end

    subgraph PORTS["Exposed Ports"]
        P80["Port 80\nHTTP → web"]
        P443["Port 443\nHTTPS → websecure"]
        P9000["Port 9000\nDashboard · /dashboard"]
        P8555["Port 8555 TCP\nRTSP stream"]
        P8554["Port 8554 UDP\nRTSP stream"]
        P9100["Port 9100\nMetrics"]
    end

    subgraph WORKLOADS["Kubernetes Services"]
        JELLYFIN["fa:fa-server jellyfin\njellyfin.app.rick.expresso.lan"]
        PIHOLE["fa:fa-globe pihole\npihole.app.rick.expresso.lan/admin"]
        RTSP["fa:fa-wifi v4l2rtspserver\nrtsp0.app.rick.expresso.lan"]
    end

    EXT -->|"loadBalancerSourceRanges\n10.50.0.0/24"| LB
    LB --> P80
    LB --> P443
    LB --> P9000
    LB --> P8555
    LB --> P8554
    LB --> P9100
    INT_SVC --> P9000
    INT_SVC --> P8555
    INT_SVC --> P8554
    INT_SVC --> P9100
    P443 --> JELLYFIN
    P443 --> PIHOLE
    P8555 --> RTSP
    P8554 --> RTSP

    style EXT fill:#1d4ed8,stroke:#ccc,color:#fff
    style LB fill:#1d4ed8,stroke:#ccc,color:#fff
    style INT_SVC fill:#b91c1c,stroke:#ccc,color:#fff
    style P80 fill:#0f766e,stroke:#ccc,color:#fff
    style P443 fill:#0f766e,stroke:#ccc,color:#fff
    style P9000 fill:#b91c1c,stroke:#ccc,color:#fff
    style P8555 fill:#b91c1c,stroke:#ccc,color:#fff
    style P8554 fill:#b91c1c,stroke:#ccc,color:#fff
    style P9100 fill:#b91c1c,stroke:#ccc,color:#fff
    style JELLYFIN fill:#15803d,stroke:#ccc,color:#fff
    style PIHOLE fill:#15803d,stroke:#ccc,color:#fff
    style RTSP fill:#15803d,stroke:#ccc,color:#fff
```

**Traefik values (prod):**

| Setting | Value |
|---------|-------|
| Image | `rancher/mirrored-library-traefik:3.6.9` |
| Service type | `LoadBalancer` (single, IPv4) |
| LB IP | 10.50.0.24 (macvlan ingress network) |
| LB source ranges | 10.50.0.0/24 |
| Internal ClusterIP source ranges | 10.10.0.0/16, 10.11.0.0/16, 10.16.0.0/16, 10.43.0.0/16 |
| Forwarded headers trusted IPs | 10.50.0.0/24, all internal subnets |
| Node selector | `svccontroller.k3s.cattle.io/enablelb=true` |
| TLS store | `default-certificate` (issued by `root-ca` ClusterIssuer) |
| Dashboard | `/dashboard`, `/api` on port 9000 (internal only) |
| RTSP TCP | 8555 (internal only) |
| RTSP UDP | 8554 (internal only) |
| Metrics | 9100 (internal only) |

---

## DNS

DNS resolution uses a two-tier approach: pihole handles LAN-level name resolution and upstream filtering; CoreDNS handles in-cluster name rewriting.

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    CLIENT(["fa:fa-server LAN Client / Pod"])

    subgraph PIHOLE_BOX["Pi-hole — pihole.app.rick.expresso.lan"]
        PIHOLE_DNS["fa:fa-globe dnsmasq · port 1053\nBlocked: ads/tracking\nForwards unknown → 8.8.8.8 / 8.8.4.4"]

        subgraph AREC["Custom A Records"]
            A1["10.50.0.1 → expresso.lan"]
            A2["10.50.0.2 → rick.expresso.lan"]
            A3["10.50.0.11 → rpi4.expresso.lan"]
            A4["10.50.0.50 → rh-thinkpad-p1.expresso.lan"]
            A5["10.50.0.100 → r10.expresso.lan"]
        end

        subgraph CNAMES["CNAME Records"]
            C1["app.rick.expresso.lan → rick.expresso.lan"]
            C2["*.app.rick.expresso.lan → app.rick.expresso.lan"]
            C3["rick.lan / rick → rick.expresso.lan"]
        end
    end

    subgraph COREDNS_BOX["CoreDNS (in-cluster)"]
        COREDNS["fa:fa-dharmachakra CoreDNS\nRewrite: name regex\n(.*)-(rick)\\.app\\.expresso\\.lan\n→ {1}.cluster.{2}.local"]
    end

    GOOGLE(["fa:fa-cloud Google DNS\n8.8.8.8 / 8.8.4.4"])

    CLIENT -->|"DNS query"| PIHOLE_DNS
    PIHOLE_DNS -->|"known LAN hosts"| AREC
    PIHOLE_DNS -->|"in-cluster names"| COREDNS
    PIHOLE_DNS -->|"unknown / external"| GOOGLE
    COREDNS -->|"resolves to ClusterIP"| CLIENT

    style CLIENT fill:#1d4ed8,stroke:#ccc,color:#fff
    style PIHOLE_DNS fill:#15803d,stroke:#ccc,color:#fff
    style A1 fill:#0f766e,stroke:#ccc,color:#fff
    style A2 fill:#0f766e,stroke:#ccc,color:#fff
    style A3 fill:#0f766e,stroke:#ccc,color:#fff
    style A4 fill:#0f766e,stroke:#ccc,color:#fff
    style A5 fill:#0f766e,stroke:#ccc,color:#fff
    style C1 fill:#0f766e,stroke:#ccc,color:#fff
    style C2 fill:#0f766e,stroke:#ccc,color:#fff
    style C3 fill:#0f766e,stroke:#ccc,color:#fff
    style COREDNS fill:#7e22ce,stroke:#ccc,color:#fff
    style GOOGLE fill:#1d4ed8,stroke:#ccc,color:#fff
```

**DNS configuration summary:**

| Record type | Name | Value |
|-------------|------|-------|
| A | `expresso.lan` | 10.50.0.1 |
| A | `rick.expresso.lan` | 10.50.0.2 |
| A | `rpi4.expresso.lan` | 10.50.0.11 |
| A | `rh-thinkpad-p1.expresso.lan` | 10.50.0.50 |
| A | `r10.expresso.lan` | 10.50.0.100 |
| CNAME | `app.rick.expresso.lan` | `rick.expresso.lan` |
| CNAME | `*.app.rick.expresso.lan` | `app.rick.expresso.lan` |
| CNAME | `rick.lan`, `rick` | `rick.expresso.lan` |
| CNAME | `pihole.app.rick.expresso.lan` | `app.rick.expresso.lan` |
| CNAME | `jellyfin.app.rick.expresso.lan` | `app.rick.expresso.lan` |
| CNAME | `rtsp0.app.rick.expresso.lan` | `app.rick.expresso.lan` |

CoreDNS rewrite (`pkg/operators/coredns-custom/overlays/prod/`): any hostname matching `<svc>-<namespace>.app.expresso.lan` is internally resolved as `<svc>.cluster.<namespace>.local`.

Pi-hole runs on port **1053** inside its container (to avoid conflicts with systemd-resolved). The k3s service exposes it on ClusterIP port **1054**. DNS search domain on the host is `expresso.lan`, configured in the NetworkManager connection.

---

## Firewall

Firewall is managed by **firewalld** with an **nftables** backend.

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TD
    PKT(["fa:fa-network-wired Inbound Packet"])

    subgraph FW["firewalld — nftables backend"]
        ZONE["fa:fa-shield-halved Default Zone: trusted\nAll traffic accepted by default"]
        FLOW["fa:fa-network-wired NftablesFlowtable: eno1\nHW fastpath for TCP/UDP forwarding"]
        LOG["fa:fa-terminal LogDenied: all\nAll drops/rejects logged"]
        RPF["fa:fa-shield-halved IPv6 RPF: strict\nReverse path filter"]
    end

    RELOAD["fa:fa-terminal Reload policy\nINPUT:DROP · FORWARD:DROP · OUTPUT:DROP\nDuring rule reload only"]

    PKT --> ZONE
    ZONE -->|"match trusted"| FLOW
    ZONE -->|"no match"| LOG
    LOG -.->|"reload in progress"| RELOAD

    style PKT fill:#1d4ed8,stroke:#ccc,color:#fff
    style ZONE fill:#15803d,stroke:#ccc,color:#fff
    style FLOW fill:#0f766e,stroke:#ccc,color:#fff
    style LOG fill:#b45309,stroke:#ccc,color:#fff
    style RPF fill:#7e22ce,stroke:#ccc,color:#fff
    style RELOAD fill:#b91c1c,stroke:#ccc,color:#fff
```

| Setting | Value |
|---------|-------|
| Default zone | `trusted` |
| Backend | nftables |
| LogDenied | all |
| IPv6 RPFilter | strict |
| NftablesFlowtable | `eno1` (TCP/UDP fastpath) |
| Reload policy | `INPUT:DROP, FORWARD:DROP, OUTPUT:DROP` |
| FlushAllOnReload | yes |
| NftablesTableOwner | yes (exclusive ownership) |

> **Note:** Lockdown mode is configured but currently disabled in `firewalld.conf`. The default zone is `trusted`, meaning all traffic is accepted unless blocked by a specific rule.

---

## Kernel Networking (sysctl)

Applied via `deploy/butane/base/files/etc/sysctl.d/`:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `net.bridge.bridge-nf-call-iptables` | 1 | Required for k3s / container networking |
| `net.netfilter.nf_conntrack_tcp_timeout_close_wait` | 3600 | Extended TCP CLOSE_WAIT timeout |
| `net.netfilter.nf_conntrack_tcp_timeout_established` | 86400 | 24 h connection tracking for established flows |
| `net.netfilter.nf_conntrack_max` | 196608 | Increased conntrack table (container workloads) |
| `fs.inotify.max_user_watches` | 524288 | Required for large k3s manifest watches |
| `fs.inotify.max_user_instances` | 1024 | Required for controller managers |

---

## Quick Reference — IP Address Map

| Host / Service | IP | Role |
|---------------|-----|------|
| `expresso.lan` | 10.50.0.1 | LAN gateway, DNS upstream |
| `rick.expresso.lan` | 10.50.0.2 | Production host (eno1) |
| `rpi4-0` | 10.50.0.11 | k3s agent (Raspberry Pi 4) |
| `rh-thinkpad-p1.expresso.lan` | 10.50.0.50 | Workstation |
| `r10.expresso.lan` | 10.50.0.100 | Host |
| kube-vip VIP | 10.10.0.100 | Kubernetes API (HA, `server0` iface) |
| k3s-server-0 `server0` | 10.10.0.2 | Control plane node 0 |
| k3s-server-1 `server0` | 10.10.0.3 | Control plane node 1 |
| k3s-server-2 `server0` | 10.10.0.4 | Control plane node 2 |
| k3s-agent-0 `agent0` | 10.11.0.6 | Agent node (compute) |
| k3s-svclb-0 `agent0` | 10.11.0.5 | Service LB / ingress node |
| Traefik LoadBalancer | 10.50.0.24 | External ingress (macvlan) |
| k3s service CIDR | 10.43.0.0/16 | Kubernetes ClusterIP range |
| k3s pod CIDR | 10.42.0.0/16 | Default k3s pod network |
| Cluster/pod route | 10.16.0.0/16 | Routed via 10.50.0.11 (metric 90) |
