#!/usr/bin/env bash
# Bootstrap the demo cluster: fresh ArgoCD + root app. Run once against the new EKS cluster.
set -euo pipefail
cd "$(dirname "$0")"

ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.1.3}"   # ArgoCD 3.x — needed for k8s >=1.33 (terminatingReplicas diff fix)

if grep -q REPO_URL_PLACEHOLDER root-app.yaml; then
  echo "ERROR: repo URL not set. Run ./set-repo-url.sh <git-repo-url> first." >&2
  exit 1
fi

PHASE=$(kubectl get ns argocd -o jsonpath='{.status.phase}' 2>/dev/null || true)
if [ "$PHASE" = "Terminating" ]; then
  echo "==> argocd namespace is still Terminating from a previous cleanup — waiting (max 3m)"
  kubectl wait --for=delete ns/argocd --timeout=180s || {
    echo "ERROR: namespace stuck Terminating. Strip leftover finalizers and retry:" >&2
    echo "  kubectl get applications -n argocd -o name | xargs -I{} kubectl patch {} -n argocd --type merge -p '{\"metadata\":{\"finalizers\":null}}'" >&2
    exit 1
  }
fi

echo "==> Installing ArgoCD (chart ${ARGOCD_CHART_VERSION})"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "${ARGOCD_CHART_VERSION}" \
  -f argocd-values.yaml \
  --wait --timeout 10m

echo "==> Applying root app (app-of-apps)"
kubectl apply -f root-app.yaml

echo "==> Initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo

cat <<'EOF'

Done. Next — run each in its own terminal (self-healing loops):

  # ArgoCD UI -> http://localhost:8080  (admin / password above)
  while true; do kubectl -n argocd port-forward svc/argocd-server 8080:80; sleep 1; done

  # Kiali UI  -> http://localhost:20001  (available once the kiali app is synced)
  while true; do kubectl -n istio-system port-forward svc/kiali 20001:20001; sleep 1; done

Watch the sync waves: istio-base -> istiod/istio-cni -> ztunnel -> prometheus/kiali -> demo apps.
Reminder: checkout & payment have NO auto-sync — click Sync on both in the ArgoCD UI.
EOF
