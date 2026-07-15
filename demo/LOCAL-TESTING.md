# Local Testing — docker-desktop context

Dry-run of the full demo on Docker Desktop Kubernetes before touching EKS.

## Pre-flight

1. Docker Desktop → Settings → Kubernetes → **Enable Kubernetes** (running, green).
   Give the VM ≥ 4 CPU / 6 GB RAM (Settings → Resources) — istio + argocd + prometheus need headroom.
2. `kubectl config use-context docker-desktop && kubectl get nodes`
3. ArgoCD pulls from Git, not from your disk — push this folder to a repo first:

```bash
cd istio-ambient-demo
rm -f **/*.bak                       # leftover backup files, don't commit them
git init && git add -A && git commit -m "istio ambient demo"
git remote add origin <REPO_URL> && git push -u origin main
./bootstrap/set-repo-url.sh <REPO_URL>
git add -A && git commit -m "set repo url" && git push
```

## Install

```bash
kubectl config use-context docker-desktop   # make sure! bootstrap installs into current context
./bootstrap/install.sh
```

Then follow `RUNBOOK.md` from Phase 1. Everything (waves, label flip, mTLS proof,
Kiali) behaves the same as on EKS.

## docker-desktop vs EKS differences

| Topic | On docker-desktop |
|---|---|
| CNI chaining | No AWS VPC CNI here; istio-cni chains into Docker Desktop's CNI conf. The `10-aws.conflist` note is EKS-only — no values change needed, istio-cni auto-detects. |
| Nodes | Single node — ztunnel DaemonSet = 1 pod; checkout & payment share the node. mTLS still applies (HBONE between pods via the same ztunnel). |
| tcpdump money shot | `kubectl debug node/docker-desktop -it --image=nicolaka/netshoot -- tcpdump -i any -A -s 120 'tcp port 8080 or tcp port 15008'` |
| Untaint controller | Irrelevant locally (no autoscaling) — already commented out in values. |

## Known risk — ambient on Docker Desktop

Istio officially validates ambient on **kind/minikube/k3d**, not Docker Desktop.
It generally works on recent Docker Desktop versions, but if `istio-cni-node` or
ztunnel fail to initialize (CrashLoopBackOff, "failed to find CNI config" errors),
don't fight it — fall back to kind, which is the supported local platform:

```bash
kind create cluster --name ambient-demo
kubectl config use-context kind-ambient-demo
./bootstrap/install.sh
```

Same repo, same everything — only the context changes.

## Cleanup

```bash
./bootstrap/cleanup.sh                    # guarded: confirms context, refuses prod/sbox
DELETE_CRDS=true ./bootstrap/cleanup.sh   # also removes istio + gateway-api CRDs
```

(Locally you can also just Reset Kubernetes in Docker Desktop.)
