#!/bin/sh
# Bootstraps this GitOps setup on a brand new cluster, from zero to a
# self-managing ArgoCD. Captures what used to be 3 separate commands typed
# by hand (helm install argocd -> kubectl apply AppProject -> kubectl apply
# root) as one script, so rebuilding the cluster never depends on anyone
# remembering the exact sequence.
#
# Still a human runs this, still only once per cluster — this is NOT an
# attempt to automate the bootstrap away (that's an unavoidable
# chicken-and-egg: ArgoCD has to exist before anything can be managed by
# ArgoCD). The point is making the one-time manual step reproducible code
# instead of tribal knowledge.
#
# Run from a directory containing both repos checked out side by side:
#   devops/
#     gitops/           (this repo)
#     platform-gitops/
#
# PREREQUISITE — cannot be automated or put through Vault, must exist
# BEFORE this script runs:
#   platform-gitops is a PRIVATE repo, and root's very first sync needs to
#   read it before Vault/Vault Secrets Operator exist to do that for any
#   other secret. Register it with ArgoCD by hand once:
#     argocd repo add https://github.com/heloooo-maker/platform-gitops.git \
#       --username <github-username> --password <github PAT, repo scope>
#   (needs `argocd login` against the ArgoCD this script installs below —
#   do that first, or run this via `kubectl exec` against the repo-server
#   if argocd CLI isn't configured yet)

set -e

GITOPS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVOPS_DIR="$(cd "$GITOPS_DIR/.." && pwd)"
PLATFORM_DIR="$DEVOPS_DIR/platform-gitops"

if [ ! -d "$PLATFORM_DIR" ]; then
  echo "Expected platform-gitops checked out at $PLATFORM_DIR - clone it first:"
  echo "  git clone https://github.com/heloooo-maker/platform-gitops.git $PLATFORM_DIR"
  exit 1
fi

echo "=== 1/4: Install ArgoCD ==="
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd \
  --version 10.9.2 \
  --namespace argocd-thanhlam --create-namespace \
  -f "$PLATFORM_DIR/argocd/values.yaml"

echo "=== 2/4: Wait for argocd-server to be ready ==="
kubectl -n argocd-thanhlam rollout status deploy/argocd-thanhlam-server --timeout=180s

echo "=== 3/4: Apply the platform AppProject (bootstrap object - must exist"
echo "    before an Application can declare project: platform) ==="
kubectl apply -f "$PLATFORM_DIR/bootstrap/appproject.yaml"

cat <<'EOF'

=== PAUSE: register the private platform-gitops repo with ArgoCD ===
root's first sync needs to read heloooo-maker/platform-gitops (private),
before Vault/VSO exist to do that any other way. If you haven't already:

  argocd login argocd.thanhlam.online   # or: kubectl -n argocd-thanhlam port-forward svc/argocd-thanhlam-server 8080:443
  argocd repo add https://github.com/heloooo-maker/platform-gitops.git \
    --username <github-username> --password <github PAT, repo scope>

Press Enter once that's done to continue, or Ctrl+C to do it later and
re-run from step 4 (`kubectl apply -f bootstrap/root-application.yaml`
+ `argocd app sync root`) yourself.
EOF
read -r _

echo "=== 4/4: Apply root (app-of-apps) and sync it ==="
echo "    NOTE - first-ever bootstrap only: root's bootstrap/ content targets"
echo "    vault-thanhlam and tunnel-system before anything else creates them"
echo "    (platform-utilities/platform-repo-charts use CreateNamespace=true,"
echo "    but only for THEIR OWN destination, not for namespaces referenced"
echo "    by root's own raw manifests). Discovered 2026-10-10: pre-create"
echo "    both or this sync fails with 'namespace not found'."
kubectl create namespace vault-thanhlam --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace tunnel-system --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$GITOPS_DIR/bootstrap/root-application.yaml"
argocd app sync root

cat <<'EOF'

=== Bootstrap done. Still needed by hand (cannot go through Vault/GitOps): ===
  1. vault-kms: `sh platform-gitops/vault-kms-bootstrap.sh` steps 1-6
     (init/unseal vault-kms, create the transit autounseal key + token)
  2. kubectl create secret generic vault-kms-transit-token -n vault-thanhlam \
       --from-literal=token=<client_token from vault-kms-bootstrap.sh step 6>
  3. Once platform/vault is up and auto-unsealed: `vault operator init` on
     it, BY HAND (no CronJob does this anymore - see platform/vault/
     values.yaml's comment for why). Keep the root token only long enough
     to run the next step, then revoke it.
  4. sh platform-gitops/vault-config-operator-bootstrap.sh (uses that root
     token once, to create the narrowly-scoped role every CR in
     bootstrap/vault-config-operator-crs.yaml authenticates as - then the
     root token gets revoked and is never needed again)
  5. ArgoCD picks up bootstrap/vault-config-operator-crs.yaml on its own
     from here - policies, roles, the audit device, and the JFrog/Grafana
     RandomSecrets all reconcile automatically, no more manual
     `vault kv put` for those. Only genuinely external credentials still
     need seeding by hand (see each one's comment in
     platform-gitops/cloudflared/values.yaml and
     platform-gitops/bootstrap/vault-auth-argocd-thanhlam.yaml):
       vault kv put secret/cloudflared credentials.json=@<tunnel-id>.json
       vault kv put secret/image-updater-git username=argocd-image-updater password=<github PAT>

=== EXPECTED, not a bug: 3 pods will sit in ImagePullBackOff ===
  resoweb, freelance-agency-template, charts-repo all still reference
  harbor-pull-secret / harbor.thanhlam.online (Harbor was retired, JFrog
  never finished replacing it — see platform-gitops/jfrog/values.yaml).
  Leave them red until JFrog is up and configured (login, create
  docker-local/helm-local repos, create a token), then come back and
  cut these 3 + image-updater over to it.
EOF
