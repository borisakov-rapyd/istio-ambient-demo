#!/usr/bin/env bash
# Reset all demo toggles to the pre-demo baseline (everything false) and push.
# Usage: ./bootstrap/reset-demo.sh          # reset + commit + push
#        ./bootstrap/reset-demo.sh --local  # reset files only, no git actions
set -euo pipefail
cd "$(dirname "$0")/.."

cp bootstrap/baseline/checkout-values.yaml apps/checkout/values.yaml
cp bootstrap/baseline/payment-values.yaml  apps/payment/values.yaml

echo "==> Demo values reset to baseline:"
git --no-pager diff --stat -- apps/ || true

if [ "${1:-}" = "--local" ]; then
  echo "(--local: not committing — review and push yourself)"
  exit 0
fi

if git diff --quiet -- apps/; then
  echo "Already at baseline — nothing to commit."
else
  git add apps/
  git commit -m "reset demo values to baseline"
  git push
  echo "Pushed. Sync checkout + payment in ArgoCD to apply."
fi
