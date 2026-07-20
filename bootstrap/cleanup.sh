#!/usr/bin/env bash
# Tear down EVERYTHING the demo installed: apps, istio, kiali, prometheus, argocd.
# Safety-first: shows the target context, requires explicit confirmation, and
# refuses to run against protected clusters (prod/sbox are read-only, always).
set -euo pipefail
cd "$(dirname "$0")"

CTX=$(kubectl config current-context)

# ---- guardrails ------------------------------------------------------------
case "$CTX" in
  *prod*|*sbox*)
    echo "REFUSED: current context '$CTX' looks like a protected environment (prod/sbox)." >&2
    exit 1;;
  *intg*|*qa*|*devops*)
    echo "WARNING: '$CTX' looks like a shared Rapyd cluster, not a demo cluster." >&2;;
esac

echo "This will DELETE the entire demo from context:"
echo ""
echo "    $CTX"
echo ""
echo "Resources to be removed:"
echo "  - ArgoCD apps: root, appsets, gateway-api-crds, istio*, kiali, prometheus, checkout, payment"
echo "  - Helm release: argocd"
echo "  - Namespaces: checkout, payment, monitoring, istio-system, argocd"
read -r -p "Type the context name to confirm deletion: " CONFIRM
[ "$CONFIRM" = "$CTX" ] || { echo "Confirmation mismatch — aborting."; exit 1; }

# ---- teardown ---------------------------------------------------------------
echo "==> Deleting root app (cascades to all ArgoCD-managed apps)"
kubectl delete -f root-app.yaml --ignore-not-found

echo "==> Waiting for applications to be cleaned up (max 5m)"
for i in $(seq 1 60); do
  LEFT=$(kubectl -n argocd get applications --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$LEFT" = "0" ] && break
  sleep 5
done

echo "==> Stripping finalizers from any leftover Applications (prevents stuck namespace)"
kubectl get applications -n argocd -o name 2>/dev/null | \
  xargs -r -I{} kubectl patch {} -n argocd --type merge -p '{"metadata":{"finalizers":null}}' || true

echo "==> Uninstalling ArgoCD"
helm uninstall argocd -n argocd --ignore-not-found 2>/dev/null || true

echo "==> Deleting namespaces (Prune=false kept them alive on purpose)"
kubectl delete ns checkout payment monitoring istio-system --ignore-not-found --timeout=120s || true
kubectl delete ns argocd --ignore-not-found --timeout=120s || true

echo "==> Waiting for namespaces to be FULLY gone (a re-install into a Terminating ns fails)"
for ns in checkout payment monitoring istio-system argocd; do
  kubectl wait --for=delete "ns/$ns" --timeout=180s 2>/dev/null || true
done

if [ "${DELETE_CRDS:-false}" = "true" ]; then
  echo "==> Deleting Istio + Gateway API CRDs (DELETE_CRDS=true)"
  kubectl get crd -o name | grep -E 'istio\.io|gateway\.networking\.k8s\.io' | xargs -r kubectl delete
else
  echo "==> Keeping CRDs (set DELETE_CRDS=true to remove istio.io + gateway.networking.k8s.io CRDs)"
fi

echo ""
echo "Done. Remaining istio/demo traces (should be empty):"
kubectl get ns 2>/dev/null | grep -E 'checkout|payment|istio|argocd|monitoring' || echo "  none"
