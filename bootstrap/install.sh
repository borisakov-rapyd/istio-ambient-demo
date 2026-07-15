#!/usr/bin/env bash
# Bootstrap the demo cluster: fresh ArgoCD + root app. Run once against the new EKS cluster.
set -euo pipefail
cd "$(dirname "$0")"

ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.11}"   # bump to latest before demo day

if grep -q REPO_URL_PLACEHOLDER root-app.yaml; then
  echo "ERROR: repo URL not set. Run ./set-repo-url.sh <git-repo-url> first." >&2
  exit 1
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

Done. Next:
  kubectl -n argocd port-forward svc/argocd-server 8080:80
  open http://localhost:8080   (user: admin, password above)

Watch the sync waves: istio-base -> istiod/istio-cni -> ztunnel -> prometheus/kiali -> demo apps.
EOF
