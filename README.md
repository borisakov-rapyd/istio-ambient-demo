# Istio Ambient Mesh — GitOps Demo

A self-contained, GitOps-driven demo of **Istio ambient mode** on Kubernetes.
One `install.sh` bootstraps Argo CD, which then installs Istio (ambient), an
observability stack, and two example services — all from this repo. From there,
every step of the demo is a **Git change**: enroll services into the mesh, add
an L7 waypoint, apply authorization, and enforce strict mTLS.

> Presented at CNCF Cloud Native Tel Aviv — *"Istio Ambient Mode: service mesh
> without the sidecars."*

---

## What it demonstrates

| Step | Change in Git | What you see |
|------|---------------|--------------|
| **Enroll** | `istio.enabled: true` | services join the mesh live — traffic becomes mTLS, zero app changes |
| **Observe** | `waypoint.enabled: true` | HTTP golden signals (rates, codes, latency) appear in Kiali |
| **Authorize (L7)** | `l7Authz.enabled: true` | only `GET /api/*` allowed; other methods get `403` |
| **Authorize (L4)** | `authorizationPolicy.enabled: true` | only listed workload identities may call the service |
| **Encrypt strictly** | `strictMtls: true` | non-mesh (identity-less) callers are rejected |

Two proofs run continuously so the effects are visible without packet-hunting:
a **wire sniffer** (node-level tcpdump) and an **mTLS verifier** (an unmeshed
caller that logs `OK` → `FAIL` the moment strict mTLS is enforced).

---

## Architecture

```
GitHub repo ──► Argo CD ──► installs & syncs everything below
                              │
   istiod (control plane) ────┤   xDS + SPIFFE certificates
                              │
   ┌── node ───────────────┐  │  ┌── node ───────────────┐
   │ checkout   traffic-gen │  │  │ waypoint (L7, opt.)   │
   │        │               │  │  │        │              │
   │     ztunnel (L4) ◄─────┼──HBONE :15008──► ztunnel(L4)│
   └───────────────────────┘  │  └───────────────────────┘
                              │
   Prometheus ──► Kiali  ◄────┘   telemetry (L4 from ztunnel, L7 from waypoint)
```

- **istiod** — control plane: configuration (xDS) + workload identity (mTLS certs).
- **ztunnel** — per-node L4 proxy (DaemonSet): mTLS, identity, TCP telemetry.
- **waypoint** — optional per-namespace L7 proxy: HTTP routing, metrics, authz.
- **istio-cni** — node agent that enrolls pods into the mesh (chained, non-replacing).

---

## Repository layout

```
bootstrap/           Argo CD install + root app-of-apps (the only kubectl apply)
  install.sh           one-shot bootstrap
  cleanup.sh           guarded teardown (refuses prod/sbox, scrubs node CNI)
  reset-demo.sh        restore demo values to the all-off baseline
  baseline/            canonical baseline values for the demo apps
applicationSets/     Argo CD ApplicationSets + standalone Apps
addons/              Istio (base/istiod/cni/ztunnel), Prometheus, Kiali
  <addon>/config.yaml  generator input   <addon>/values.yaml  Helm values
charts/demo-app/     Helm chart: Deployment + Service + Istio policy templates
apps/                checkout & payment (config.yaml + values.yaml each)
sniffer/             wire-sniffer (plaintext/HBONE) + mtls-verifier
```

Sync order (waves): `gateway-api-crds (-1)` → `istio-base (0)` →
`istiod, istio-cni (1)` → `ztunnel (2)` → `prometheus (3)` → `kiali (4)` →
`sniffer (5)` → demo apps (10).

---

## Quick start

Requires a Kubernetes cluster (2+ nodes recommended; not Fargate — ambient needs
real nodes), plus `kubectl`, `helm`, and `git`.

```bash
# 1. point the manifests at your fork
./bootstrap/set-repo-url.sh https://github.com/<you>/istio-ambient-demo.git
git commit -am "set repo url" && git push

# 2. bootstrap Argo CD + the root app; everything else syncs from Git
./bootstrap/install.sh
```

The script prints the Argo CD admin password and the port-forward commands for
the Argo CD and Kiali UIs. The two demo apps have auto-sync **off** by design —
Sync them from the UI to start (so the enrollment step later is a deliberate click).

## Run the demo

Everything is a Git change followed by an Argo CD sync. In order:

```bash
# enroll both services into the mesh
#   apps/checkout/values.yaml + apps/payment/values.yaml -> istio.enabled: true
# add L7 (HTTP metrics + authz needs this)
#   apps/payment/values.yaml -> istio.waypoint.enabled: true   (checkout too, for a fuller graph)
# L7 authorization: GET /api/* only
#   apps/payment/values.yaml -> istio.l7Authz.enabled: true
# strict mTLS: reject identity-less callers
#   apps/payment/values.yaml -> istio.strictMtls: true
git commit -am "..." && git push        # then Sync in Argo CD
```

Watch the effects:

```bash
kubectl -n sniffer logs -f ds/wire-sniffer        # plaintext HTTP, then encrypted
kubectl -n sniffer logs -f deploy/mtls-verifier   # OK -> FAIL when strict mTLS lands
# Kiali: Traffic Graph -> checkout + payment -> Security badge for mTLS padlocks
```

## Reset & clean up

```bash
./bootstrap/reset-demo.sh    # restore the all-off baseline, commit, push
./bootstrap/cleanup.sh       # tear the whole demo down (guarded)
```

---

## Notes & scope

This is a **demo**, tuned for clarity over production hardening:

- Argo CD runs with `server.insecure: true`; Kiali uses anonymous auth.
- `sniffer/` runs a privileged, host-network tcpdump — never ship that to a real cluster.
- Chart versions are pinned (`argo-cd 10.1.3`, `kiali 2.29.0`, `istio 1.29.2`).
  On Kubernetes ≥ 1.33 keep Argo CD recent (older versions fail diffs on
  `.status.terminatingReplicas`), and keep Kiali roughly in step with the Istio minor.

Production-minded touches that *are* included, because they were real lessons:
`istio-cni` chains into the existing CNI (doesn't replace it), `ambient.ipv6: false`,
ztunnel `terminationGracePeriodSeconds: 300`, and the istiod node-untaint controller
(`pilot.taint` + `PILOT_ENABLE_NODE_UNTAINT_CONTROLLERS`) to avoid the pod-beats-mesh
startup race on node scale-up.

## License

MIT — see [LICENSE](LICENSE).
