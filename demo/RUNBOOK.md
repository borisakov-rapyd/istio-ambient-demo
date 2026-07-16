# Live Demo Runbook — Istio Ambient Mode

Goal on stage: **plaintext traffic → one label → mTLS**, everything through GitOps.

Timebox: ~10 min inside the talk. Phases 0–2 are done BEFORE the meetup; the live part starts at Phase 3.

---

## Phase 0 — Prerequisites (before demo day)

- Fresh EKS cluster (2–3 nodes, no Fargate for the demo workloads), kubectl context set.
- Tools on the laptop: `kubectl`, `helm`, `istioctl` (same 1.29.x minor), `git`.
- Push this folder to a Git repo (public repo = zero credential hassle):

```bash
cd istio-ambient-demo
git init && git add -A && git commit -m "istio ambient demo"
git remote add origin <REPO_URL> && git push -u origin main
./bootstrap/set-repo-url.sh <REPO_URL>
git add -A && git commit -m "set repo url" && git push
```

If the repo is private: after installing ArgoCD, add credentials
(`argocd repo add <REPO_URL> --username … --password …`) before the root app syncs.

## Phase 1 — Bootstrap (before demo day, ~10 min)

```bash
./bootstrap/install.sh
kubectl -n argocd port-forward svc/argocd-server 8080:80 &
# UI: http://localhost:8080  (admin / password printed by the script)
```

Watch the waves: `istio-base` → `istiod` + `istio-cni` → `ztunnel` → `prometheus` → `kiali` → `checkout` + `payment`.

Verify the mesh is up:

```bash
kubectl -n istio-system get pods                 # istiod, istio-cni-node, ztunnel, kiali
istioctl ztunnel-config workload | head          # ztunnel is alive; demo apps NOT listed yet
kubectl -n istio-system port-forward svc/kiali 20001:20001 &
# Kiali: http://localhost:20001
```

## Phase 2 — Rehearsal checkpoint

- `checkout` and `payment` namespaces exist, pods Ready, **no** `istio.io/dataplane-mode` label.
- Traffic generator in `checkout` is hitting payment every 2s (Kiali graph appears once meshed; before that use curl).

---

## Phase 3 — LIVE: prove traffic is plaintext (~3 min)

**3a. Show Kiali "before" — we are blind:**

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001 &
# http://localhost:20001 → Traffic Graph → select checkout + payment → auto-refresh 15s
```

Traffic is flowing (traffic-gen hits payment every 2s), yet the graph is EMPTY and the
workloads show an "Out of mesh" badge. No mesh = no telemetry. Keep this tab open —
the edge will appear live after the label flip.

**3b. Call the API from inside checkout:**

```bash
kubectl -n checkout exec deploy/checkout -- \
  wget -qO- http://payment.payment.svc.cluster.local/api/charge
# JSON echo of the request — service-to-service call works, plain Kubernetes
```

**3c. Sniff it on the node — the money shot:**

```bash
NODE=$(kubectl -n payment get pod -l app=payment -o jsonpath='{.items[0].spec.nodeName}')
kubectl debug node/$NODE -it --image=nicolaka/netshoot -- \
  tcpdump -i any -A -s 120 'tcp port 8080 or tcp port 15008'
```

Audience sees **readable HTTP** — headers, JSON, everything — on the wire. In a fintech. Let that sink in.

(Keep this tcpdump running in a visible terminal for the after-shot.)

## Phase 4 — LIVE: enable the mesh with one label, via GitOps (~2 min)

```bash
# edit apps/checkout/values.yaml  -> istio.enabled: true
# edit apps/payment/values.yaml   -> istio.enabled: true
git commit -am "enroll checkout & payment into ambient mesh" && git push
```

Two enrollment modes exist in the chart (`istio.mode`) — worth 30s of narration:

- `namespace` (demo default): label on the Namespace → running pods join **live, no restart**.
- `pod`: label on the pod template → per-workload granularity (our production pattern),
  but enrollment rides a rolling restart — a pod-template change always creates a new ReplicaSet.

Switch to the ArgoCD UI: the apps turn **OutOfSync** (auto-sync is intentionally off
for checkout/payment) → narrate the diff → click **Sync** on each app yourself.
Point out: **no pod restarts** — same pods, same IPs, `kubectl -n payment get pods` shows zero restarts.

## Phase 5 — LIVE: prove it's mTLS now (~3 min)

```bash
istioctl ztunnel-config workload | grep -E 'checkout|payment'
# both workloads now listed, protocol HBONE

kubectl -n checkout exec deploy/checkout -- \
  wget -qO- http://payment.payment.svc.cluster.local/api/charge
# still works — the app noticed NOTHING
```

The tcpdump terminal: port-8080 plaintext is gone; traffic now rides **:15008 (HBONE)** — TLS gibberish.

Kiali (http://localhost:20001): Traffic Graph → namespaces `checkout`,`payment` → enable the **Security** display badge → padlocks on the edges.

## Phase 5.5 — L7 upgrade: attach a waypoint (~2 min)

Point at Kiali: TCP bytes + padlock, but the HTTP panels are empty. That's the L4/L7
split in action — ztunnel doesn't parse HTTP. Now attach the L7 proxy, via Git of course:

```bash
# apps/payment/values.yaml  -> istio.waypoint.enabled: true
# apps/checkout/values.yaml -> istio.waypoint.enabled: true   (optional but nicer graph)
git commit -am "attach waypoints: give me HTTP golden signals" && git push
# Sync in ArgoCD → a 'waypoint' deployment appears in each namespace
kubectl get gateway -n payment && kubectl get pods -n payment
```

1–2 minutes later Kiali shows istio_requests_total: request rates, response codes,
latencies — the full HTTP graph. One value flip = observability upgrade.
(Requires the gateway-api-crds app — synced automatically at wave -1.)

**L7 authorization — "who may connect" vs "what they may do":**

```bash
# apps/payment/values.yaml -> istio.l7Authz.enabled: true ; commit, push, Sync
# GET still works (allowed):
kubectl -n checkout exec deploy/checkout-traffic-gen -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://payment.payment.svc.cluster.local/api/charge   # 200
# anything else is denied by the waypoint — despite a valid mTLS identity:
kubectl -n checkout exec deploy/checkout-traffic-gen -- \
  curl -s -w '\n%{http_code}\n' -X DELETE http://payment.payment.svc.cluster.local/api/charge    # RBAC: access denied / 403
```

One-liner for the room: *ztunnel decided WHO may connect; the waypoint decides WHAT they may do.*

## Phase 6 — Bonus if time allows (~2 min)

**STRICT mTLS — reject plaintext callers:**

```bash
# apps/payment/values.yaml -> istio.strictMtls: true ; commit & push
kubectl run rogue -n default --image=curlimages/curl --rm -it --restart=Never -- \
  curl -sv --max-time 3 http://payment.payment.svc.cluster.local/api/charge
# connection reset — not in the mesh, no identity, no entry
```

**L4 authorization — identity, not IPs:**

```bash
# apps/payment/values.yaml -> istio.authorizationPolicy.enabled: true ; commit & push
kubectl -n checkout exec deploy/checkout -- wget -qO- http://payment.payment.svc... # 200, allowed
# any other meshed workload -> denied by ztunnel (L4, per SPIFFE identity)
```

---

## Reset between rehearsals

```bash
git revert HEAD~..HEAD   # or set istio.enabled back to false, push
# pods keep running; label removal un-enrolls them live
```

## Failure modes & fallbacks

| Symptom | Check |
|---|---|
| Apps not syncing | repo URL/credentials in ArgoCD; `kubectl -n argocd get applicationsets` |
| ztunnel-config empty after label | istio-cni-node logs; namespace actually has the label (`kubectl get ns -L istio.io/dataplane-mode`) |
| Kiali graph empty | prometheus-server up; wait 2× scrape interval; traffic generator running |
| No internet / cluster dead on stage | screen-recording of the full flow (record during rehearsal!) |
