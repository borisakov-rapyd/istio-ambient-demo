# Istio Ambient Mode — Live Demo (CNCF TLV Meetup)

Self-contained GitOps repo for the live demo: fresh ArgoCD on a fresh EKS cluster,
Istio ambient installed via ApplicationSet (same pattern as `devops-eks-addons-argocd`),
two demo services (`checkout`, `payment`) that join the mesh with a single label flip in Git.

## Layout

```
bootstrap/           ArgoCD helm install + root app-of-apps (the only kubectl apply)
applicationSets/     addons-appset (istio, prometheus, kiali) + demo-apps-appset
addons/              per-addon config.yaml (generator input) + values.yaml
  istio/             base / istiod / istio-cni / ztunnel — ambient enabled, v1.29.2
  prometheus/        minimal, for the Kiali graph
  kiali/             anonymous auth, view-only
charts/demo-app/     helm chart: Deployment + Service + Istio templates
                     istio.enabled=true  =>  pod label istio.io/dataplane-mode: ambient
apps/                checkout & payment (config.yaml + values.yaml each)
demo/RUNBOOK.md      the on-stage script, phase by phase
```

## Quick start

```bash
./bootstrap/set-repo-url.sh <this-repo-git-url>   # after pushing to Git
./bootstrap/install.sh                            # installs ArgoCD + root app
```

Everything else syncs from Git. See `demo/RUNBOOK.md` for the demo flow:
plaintext proof → flip `istio.enabled` → mTLS proof → (bonus) STRICT mTLS + L4 authz.

## Sync order (waves)

istio-base (0) → istiod, istio-cni (1) → ztunnel (2) → prometheus (3) → kiali (4) → demo apps (10)

## Before demo day — checklist

- [ ] Bump pinned chart versions if desired (argo-cd 10.1.3, kiali 2.4.0, prometheus 25.30.1 — verify they still resolve: `helm search repo`). Keep ArgoCD ≥ chart 8.x on k8s 1.33+ (older versions fail diffing with `.status.terminatingReplicas: field not declared in schema`).
- [ ] Public Git repo (or add repo credentials to ArgoCD)
- [ ] EKS: 2–3 regular nodes (demo workloads must NOT land on Fargate — no ambient support)
- [ ] `istioctl` 1.29.x on the presentation laptop
- [ ] Pre-pull images / full rehearsal at least once (record it as the offline fallback)
- [ ] Laptop: two visible terminals (curl + tcpdump), ArgoCD UI tab, Kiali tab

## Notes

- ArgoCD runs with `server.insecure=true` and Kiali with anonymous auth — demo settings, not production settings.
- istio-cni chains into the AWS VPC CNI (`10-aws.conflist`); it does not replace it.
- `ambient.ipv6: false`, ztunnel `terminationGracePeriodSeconds: 300` — same rollout
  tips we present in the talk; the demo values mirror production intentionally.
