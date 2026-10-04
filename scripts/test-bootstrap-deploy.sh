#!/usr/bin/env bash
# Tests infrastructure/bootstrap/deploy.sh without AWS or the network.
#
# The wrapper is copied into a throwaway repo layout next to a fake
# platform.lock and a fake site-params.env (example values only; the real
# infrastructure/site-params.env is never read). The "platform" it clones is a
# local git repo whose deploy.sh is a stub that records the environment it was
# handed, and `aws` is a stub that fails if it is ever called.
#
# Usage: bash scripts/test-bootstrap-deploy.sh   (exit 0 = all passed)

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/infrastructure/bootstrap/deploy.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$1" "$2" "$3" >&2
  fi
}

# ── Fake platform: a git repo with a recording deploy.sh and a template ──────
PLATFORM="$WORK/platform"
mkdir -p "$PLATFORM/infrastructure/bootstrap" "$WORK/bin"
cat >"$PLATFORM/infrastructure/bootstrap/deploy.sh" <<'STUB'
#!/usr/bin/env bash
{
  for k in BOOTSTRAP_STACK_NAME AWS_REGION CREATE_OIDC_PROVIDER CREATE_APEX_DNS_RECORDS \
    GITHUB_ORG GITHUB_REPO APEX_DOMAIN MEDIA_ARCHIVE_BUCKET ALLOW_STACK_CREATE \
    SITE_PARAMS_FILE; do
    printf '%s=%s\n' "$k" "${!k-}"
  done
  if [[ -v STACK_NAME ]]; then printf 'STACK_NAME=%s\n' "$STACK_NAME"; else printf 'STACK_NAME=<unset>\n'; fi
} >"$RECORD"
STUB
printf 'AWSTemplateFormatVersion: "2010-09-09"\n' >"$PLATFORM/infrastructure/bootstrap/template.yaml"
(
  cd "$PLATFORM"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  git init --quiet
  git add -A
  git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit --quiet -m stub
  git tag v0.0.0-test
)
printf '#!/usr/bin/env bash\necho "aws must not be called" >&2\nexit 99\n' >"$WORK/bin/aws"
chmod +x "$WORK/bin/aws"

# ── A fresh fake site checkout per case ──────────────────────────────────────
# new_site <params-file-body>; sets SITE to the checkout root.
new_site() {
  SITE="$WORK/site-$((++N))"
  mkdir -p "$SITE/infrastructure/bootstrap"
  cp "$SRC" "$SITE/infrastructure/bootstrap/deploy.sh"
  printf 'platform_repo: example/platform\nplatform_ref: v0.0.0-test\n' >"$SITE/platform.lock"
  printf '%s\n' "$1" >"$SITE/infrastructure/site-params.env"
  RECORD="$WORK/record-$N"
  rm -f "$RECORD"
}
N=0

run_wrapper() { # run_wrapper [VAR=value ...]; sets RC and OUT
  set +e
  OUT="$(env "PATH=$WORK/bin:$PATH" "PLATFORM_URL=file://$PLATFORM" "RECORD=$RECORD" "$@" \
    bash "$SITE/infrastructure/bootstrap/deploy.sh" 2>&1)"
  RC=$?
  set -e
}

# ── Case 1: pins the live bootstrap identity and parameters ──────────────────
# The fake file mimics a site-params.env: a proxy STACK_NAME, plus values that
# disagree with the live stack and must be overridden.
new_site 'export GITHUB_REPO="example.net"
export APEX_DOMAIN="example.net"
export GITHUB_ORG="example-org"
export STACK_NAME="example-net-oauth-proxy"
export CREATE_OIDC_PROVIDER="true"
export CREATE_APEX_DNS_RECORDS="true"
export MEDIA_ARCHIVE_BUCKET="example-net-media"
export AWS_REGION="eu-west-1"'
run_wrapper BOOTSTRAP_STACK_NAME=example-net-oauth-proxy CREATE_APEX_DNS_RECORDS=true
check "case 1 exits 0" "0" "$RC"
EXPECTED="BOOTSTRAP_STACK_NAME=jodidaniel-com-bootstrap
AWS_REGION=us-east-1
CREATE_OIDC_PROVIDER=false
CREATE_APEX_DNS_RECORDS=false
GITHUB_ORG=jodidaniel
GITHUB_REPO=example.net
APEX_DOMAIN=example.net
MEDIA_ARCHIVE_BUCKET=jodidaniel-com-media-archive
ALLOW_STACK_CREATE=
SITE_PARAMS_FILE=$SITE/infrastructure/site-params.env
STACK_NAME=<unset>"
check "case 1 platform script got the pinned stack name and live parameters" \
  "$EXPECTED" "$(cat "$RECORD" 2>/dev/null || echo '<platform script did not run>')"

# ── Case 2: the caller's own STACK_NAME is handed back, not the file's ───────
new_site 'export STACK_NAME="example-net-oauth-proxy"'
run_wrapper STACK_NAME=caller-value
check "case 2 exits 0" "0" "$RC"
check "case 2 restores the caller's STACK_NAME" "STACK_NAME=caller-value" \
  "$(grep '^STACK_NAME=' "$RECORD" 2>/dev/null || echo '<platform script did not run>')"

# ── Case 3: refuses when the bootstrap name is the proxy's STACK_NAME ────────
new_site 'export STACK_NAME="jodidaniel-com-bootstrap"'
run_wrapper
check "case 3 exits non-zero" "1" "$RC"
check "case 3 never reaches the platform script" "absent" "$([[ -e "$RECORD" ]] && echo present || echo absent)"
check "case 3 says it refused" "yes" "$([[ "$OUT" == *"Refusing: the bootstrap stack name jodidaniel-com-bootstrap is the STACK_NAME"* ]] && echo yes || echo no)"
check "case 3 made no platform checkout" "absent" "$([[ -e "$SITE/.cms-platform" ]] && echo present || echo absent)"

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
