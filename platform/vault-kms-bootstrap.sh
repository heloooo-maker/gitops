#!/bin/sh
# Reference only - run by hand, NOT part of any ApplicationSet/CronJob.
#
# platform/vault-kms exists only to be the Transit auto-unseal backend for
# platform/vault. Deliberately not automated: the whole point of splitting
# the unseal key across trusted operators (Shamir) is that no automated
# process gets to hold it and unseal on its own - see the "why a CronJob
# defeats the purpose of seal/unseal" discussion this file's git history
# came out of. So this Vault is unsealed by hand, by whoever holds the key
# printed in step 2, and that should be rare: this pod only needs to
# restart if it crashes, gets rescheduled, or the chart/values change.
#
# Run each step with:
#   kubectl -n vault-kms-thanhlam exec -it deploy/vault-kms -- sh
# (adjust the pod/resource name to whatever `kubectl -n vault-kms-thanhlam
# get pods` actually shows - the vault chart names it after the release).
#
# Steps 1-2 run ONCE EVER (the first time this Vault exists). Re-running
# `vault operator init` on an already-initialized Vault is a hard error, so
# there's nothing to accidentally redo here.

set -e
export VAULT_ADDR=http://127.0.0.1:8200

# 1. Initialize with a single key share - one operator, no quorum needed
#    for a homelab. WRITE DOWN "Unseal Key 1" and "Initial Root Token"
#    somewhere OUTSIDE this cluster (password manager, paper, whatever) -
#    this is the one and only place they will ever be shown.
vault operator init -key-shares=1 -key-threshold=1

# 2. Unseal with the key from step 1. Needed again every time this pod
#    restarts - that's the manual step you're signing up for by choosing
#    this over an automated unsealer.
vault operator unseal '<Unseal Key 1 from step 1>'

# 3. Log in with the root token from step 1 for the one-time setup below.
export VAULT_TOKEN='<Initial Root Token from step 1>'

# 4. Enable the transit secrets engine and create the key platform/vault
#    will encrypt/decrypt its own master key with. NEVER rotate or delete
#    this key once platform/vault is using it - doing so permanently
#    strands platform/vault's data (`transit/keys/autounseal/rotate` is for
#    a deliberate, planned re-key, not something to run casually).
vault secrets enable transit
vault write -f transit/keys/autounseal

# 5. A policy scoped to exactly what platform/vault needs - encrypt/decrypt
#    against that one key, nothing else. Not root, not "manage transit".
vault policy write autounseal - <<'EOF'
path "transit/encrypt/autounseal" {
  capabilities = ["update"]
}
path "transit/decrypt/autounseal" {
  capabilities = ["update"]
}
EOF

# 6. A long-lived (but revocable, non-root) orphan token scoped to that
#    policy. platform/vault uses this, not the root token, for every
#    encrypt/decrypt call it makes on every boot.
vault token create -policy=autounseal -period=768h -orphan -format=json
# ^ copy the "client_token" value out of this, then from your own machine
#   (kubectl context, not inside this pod) run:
#
#   kubectl create secret generic vault-kms-transit-token \
#     -n vault-thanhlam --from-literal=token='<client_token from above>'
#
# platform/vault's extraSecretEnvironmentVars (platform/vault/values.yaml)
# reads VAULT_SEAL_TRANSIT_TOKEN from exactly that Secret. Once it exists,
# (re)deploy/restart platform/vault and it will auto-unseal via this Vault
# from then on, with no further manual steps on platform/vault's side.
#
# This token has period=768h (32 days) with auto-renewal
# (disable_renewal = "false" in the seal config) - platform/vault keeps it
# alive by using it, so this only matters if platform/vault is down long
# enough to miss every renewal window. If that ever happens, repeat step 6
# only (steps 1-5 stay valid - the key and policy don't need recreating).
