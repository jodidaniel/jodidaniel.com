#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Bootstrap AWS account for a cms-platform site (DELEGATING WRAPPER)
# =============================================================================
#
# This is the file the scaffolder (scaffold/create-site.js) emits into a NEW
# consuming site as `infrastructure/bootstrap/deploy.sh`. The site does NOT
# vendor the bootstrap CloudFormation template — it is the single source of
# truth in cms-platform, so a fix made there (e.g. CloudFront
# ErrorCachingMinTTL=0) flows to every consumer on the next platform_ref bump.
#
# How it works (mirrors the repo-wide ".cms-platform/ checkout-at-platform_ref"
# pattern the reusable-workflow callers use):
#   1. Read platform_repo + platform_ref from platform.lock.
#   2. Check the platform out at that ref into .cms-platform/ (gitignored).
#   3. Source infrastructure/site-params.env for the site identity, then
#      delegate to .cms-platform/infrastructure/bootstrap/deploy.sh.
#
# NOTE for a LIVE apex: the platform template gates the apex/www A-records on
# CreateApexDnsRecords (DEFAULT false, safe for pre-go-live sites). Once your
# site is live at its apex, export CREATE_APEX_DNS_RECORDS=true (here or in
# site-params.env) so a redeploy never deletes the production apex/www records.
# The platform script creates a change set, prints it, and refuses to execute
# one that removes or replaces a resource unless ALLOW_DESTRUCTIVE_CHANGES=1.
#
# NOTE on stack names: site-params.env exports STACK_NAME for the OAuth proxy
# stack. This wrapper puts STACK_NAME back to what it was before sourcing the
# file, and passes the file's path as SITE_PARAMS_FILE. The platform script
# names the bootstrap stack from BOOTSTRAP_STACK_NAME (default
# <prefix>-bootstrap), ignores a STACK_NAME equal to the file's, and refuses a
# bootstrap stack name equal to it. See cms-platform infrastructure/README.md,
# "The STACK_NAME collision".
#
# jodidaniel.com SPECIFICS (this copy differs from the scaffolded template):
# the live bootstrap stack is `jodidaniel-com-bootstrap` (us-east-1), and this
# wrapper PINS its identity and the parameters the live stack was deployed with,
# because the platform script re-sends every parameter on each run and a missing
# one silently reverts to the script's default:
#   BOOTSTRAP_STACK_NAME=jodidaniel-com-bootstrap   (never the proxy STACK_NAME)
#   CREATE_OIDC_PROVIDER=false   (the account's one GitHub OIDC provider exists)
#   CREATE_APEX_DNS_RECORDS=false (the apex alias is not managed by this stack)
#   GITHUB_ORG=jodidaniel, MEDIA_ARCHIVE_BUCKET=jodidaniel-com-media-archive
# They override the caller's environment and site-params.env on purpose. The
# wrapper refuses, before any platform checkout or AWS call, if the bootstrap
# stack name equals site-params.env's STACK_NAME (the OAuth proxy stack).
# Creating the stack needs ALLOW_STACK_CREATE=1, which this wrapper never sets;
# it exists already, so an ordinary run is an update.
#
# Prerequisites: AWS CLI v2, git, Ruby, python3, AWS credentials.
# Usage:  bash infrastructure/bootstrap/deploy.sh   (idempotent)
# =============================================================================

set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

command -v aws >/dev/null 2>&1 || error "AWS CLI not found."
command -v git >/dev/null 2>&1 || error "git not found — needed to check out the cms-platform bootstrap template."

# ── Locate repo root + platform.lock (bootstrap/ is TWO levels below root) ───
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOCK_FILE="$REPO_ROOT/platform.lock"
[[ -f "$LOCK_FILE" ]] || error "platform.lock not found at $LOCK_FILE"

read_lock() {
  # shellcheck disable=SC2016  # awk field refs ($1/$2), not shell expansion.
  awk -v k="$1" '$1==k":" {print $2; exit}' "$LOCK_FILE"
}
PLATFORM_REPO="${PLATFORM_REPO:-$(read_lock platform_repo)}"
PLATFORM_REF="${PLATFORM_REF:-$(read_lock platform_ref)}"
[[ -n "$PLATFORM_REPO" ]] || error "platform_repo not found in $LOCK_FILE"
[[ -n "$PLATFORM_REF" ]] || error "platform_ref not found in $LOCK_FILE"

# ── Load site parameters (GITHUB_REPO, APEX_DOMAIN, …) ──────────────────────
PARAMS_FILE="$REPO_ROOT/infrastructure/site-params.env"
PROXY_STACK_NAME=""
if [[ -f "$PARAMS_FILE" ]]; then
  info "Sourcing $PARAMS_FILE"
  # The file's STACK_NAME is the OAuth proxy stack's; never hand it on. Unset it
  # first so what the file leaves behind is exactly the file's own value.
  if [[ -v STACK_NAME ]]; then STACK_NAME_BEFORE="$STACK_NAME"; else unset STACK_NAME_BEFORE; fi
  unset STACK_NAME
  set -a; # shellcheck disable=SC1090
  source "$PARAMS_FILE"; set +a
  PROXY_STACK_NAME="${STACK_NAME-}"
  if [[ -v STACK_NAME_BEFORE ]]; then export STACK_NAME="$STACK_NAME_BEFORE"; else unset STACK_NAME; fi
  export SITE_PARAMS_FILE="$PARAMS_FILE"
else
  warn "infrastructure/site-params.env not found — relying on already-exported env / platform defaults."
fi

# ── Pin the live bootstrap stack's identity and parameters ───────────────────
# Forced, not defaulted: a stale shell variable or a missing line in
# site-params.env must not change what the live stack is updated to.
export BOOTSTRAP_STACK_NAME="jodidaniel-com-bootstrap"
export AWS_REGION="us-east-1"
export CREATE_OIDC_PROVIDER="false"
export CREATE_APEX_DNS_RECORDS="false"
export GITHUB_ORG="jodidaniel"
export MEDIA_ARCHIVE_BUCKET="jodidaniel-com-media-archive"
export GITHUB_REPO="${GITHUB_REPO:-jodidaniel.com}"
export APEX_DOMAIN="${APEX_DOMAIN:-jodidaniel.com}"
if [[ -n "$PROXY_STACK_NAME" && "$BOOTSTRAP_STACK_NAME" == "$PROXY_STACK_NAME" ]]; then
  error "Refusing: the bootstrap stack name ${BOOTSTRAP_STACK_NAME} is the STACK_NAME in ${PARAMS_FILE}, the OAuth proxy stack. Nothing was deployed."
fi

# ── Check the platform out at platform_ref into .cms-platform/ ──────────────
PLATFORM_DIR="$REPO_ROOT/.cms-platform"
PLATFORM_URL="${PLATFORM_URL:-https://github.com/${PLATFORM_REPO}.git}"
info "Platform: ${PLATFORM_REPO}@${PLATFORM_REF}"
info "Checking platform out into .cms-platform/ …"
rm -rf "$PLATFORM_DIR"
git clone --quiet --depth 1 --branch "$PLATFORM_REF" "$PLATFORM_URL" "$PLATFORM_DIR" \
  || error "Failed to check out ${PLATFORM_REPO}@${PLATFORM_REF} into .cms-platform/"

PLATFORM_DEPLOY="$PLATFORM_DIR/infrastructure/bootstrap/deploy.sh"
PLATFORM_TEMPLATE="$PLATFORM_DIR/infrastructure/bootstrap/template.yaml"
[[ -f "$PLATFORM_TEMPLATE" ]] || error "Platform bootstrap template missing: $PLATFORM_TEMPLATE"
[[ -f "$PLATFORM_DEPLOY" ]] || error "Platform bootstrap deploy script missing: $PLATFORM_DEPLOY"
success "Platform checked out — deploying from $PLATFORM_TEMPLATE"

# ── Delegate to the platform's bootstrap deploy.sh ─────────────────────────
exec bash "$PLATFORM_DEPLOY"
