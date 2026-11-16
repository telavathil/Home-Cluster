#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
need tofu
need jq
need ssh
need curl
tofu -chdir="$INFRA" fmt -check -recursive
# SSL_CERT_FILE holds only the PVE CA and would replace system roots for the registry.
env -u SSL_CERT_FILE tofu -chdir="$INFRA" init -input=false -lockfile=readonly
tofu -chdir="$INFRA" validate
for script in "$ROOT"/scripts/*.sh; do bash -n "$script"; done
