#!/usr/bin/env bash
# Set the git repo URL in every manifest that references this repo.
# Usage: ./set-repo-url.sh https://github.com/<you>/istio-ambient-demo.git
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <git-repo-url>"; exit 1; }
URL="$1"
cd "$(dirname "$0")/.."

FILES=$(grep -rl 'REPO_URL_PLACEHOLDER\|repoURL:' bootstrap/root-app.yaml applicationSets/ | sort -u)
for f in $FILES; do
  # replace the placeholder or any previously-set demo repo URL
  sed -i.bak -E "s|REPO_URL_PLACEHOLDER|${URL}|g; s|(repoURL: ).*istio-ambient-demo.*|\1${URL}|g" "$f"
  rm -f "$f.bak"
done
echo "Repo URL set to ${URL} in:"
echo "$FILES"
echo "NOTE: if the repo is private, add repo credentials to ArgoCD before syncing."
