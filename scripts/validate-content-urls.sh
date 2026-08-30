#!/usr/bin/env bash
#
# Validate every external URL that appears in this site's content.
#
# Why this is not just "curl every link and fail on non-200": six of the hosts
# this site links to sit behind Cloudflare (or LinkedIn's authwall) and answer
# 403/999 to ANY automated client while serving humans normally. A checker that
# treats those as broken is red forever and gets ignored, which is worse than
# no checker. So the exit code distinguishes:
#
#   OK           2xx/3xx — reachable.
#   BOT-BLOCKED  a challenge page (Cloudflare / Akamai / Imperva / LinkedIn 999).
#                NOT a failure: the URL is fine for a human, and no automated
#                client can confirm it. Reported so a person can eyeball it.
#   DEAD         4xx/5xx with no challenge signature, or DNS/connection failure.
#                This is what fails the run.
#
# Usage:  bash scripts/validate-content-urls.sh [--strict]
#         --strict also fails on BOT-BLOCKED (use when running from a network
#         that is NOT expected to be challenged, e.g. a developer laptop).
set -uo pipefail

cd "$(dirname "$0")/.."

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

# Every place content can carry an outbound link.
SOURCES=(_media _events _data _accomplishments _education _experience _expertise index.html)

mapfile -t PAIRS < <(
  grep -rhoE '"https?://[^"]+"' "${SOURCES[@]}" 2>/dev/null \
    | tr -d '"' | sort -u
)

if [ "${#PAIRS[@]}" -eq 0 ]; then
  echo "no URLs found in content — refusing to report success over an empty set" >&2
  exit 2
fi

dead=0; blocked=0; ok=0

for url in "${PAIRS[@]}"; do
  code=$(curl -sS -A "$UA" -L --max-time 45 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null) || code="000"
  body=""
  if [ "$code" = "000" ] || [ "$code" -ge 400 ] 2>/dev/null; then
    # NO pipe into `head -c` here, and the omission is load-bearing. `head`
    # exits at its byte limit, the writer upstream takes SIGPIPE, and under
    # `pipefail` the whole substitution reports failure — so a `|| body=""`
    # fallback would blank a body that was fetched perfectly well, and every
    # challenge page would then classify as DEAD. (Observed doing exactly that
    # on the first run of this script.) Fetch whole, truncate in the shell.
    # curl without --fail exits 0 on a 403, so the body IS the challenge page.
    body=$(curl -sS -A "$UA" -L --max-time 45 --compressed "$url" 2>/dev/null)
    body=${body:0:4000}
  fi

  # Here-string, never a pipe into grep -q: grep exits at the first match and a
  # large body then makes the writer take SIGPIPE, which under pipefail reads
  # as "not found" for content that IS present.
  sig=""
  if grep -qiE 'cloudflare|cf-browser-verification|just a moment|attention required|ray id' <<<"$body"; then
    sig="Cloudflare challenge"
  elif grep -qiE 'akamai|incapsula|imperva|perimeterx|px-captcha' <<<"$body"; then
    sig="WAF challenge"
  elif [ "$code" = "999" ]; then
    sig="LinkedIn authwall"
  elif [ "$code" = "403" ] && [ -n "$body" ]; then
    sig="403 with a rendered page (JS/bot gate)"
  fi

  if [ "$code" != "000" ] && [ "$code" -lt 400 ] 2>/dev/null; then
    ok=$((ok + 1))
    printf 'OK           %-4s %s\n' "$code" "$url"
  elif [ -n "$sig" ]; then
    blocked=$((blocked + 1))
    printf 'BOT-BLOCKED  %-4s %s  (%s)\n' "$code" "$url" "$sig"
  else
    dead=$((dead + 1))
    printf 'DEAD         %-4s %s\n' "$code" "$url"
  fi
done

echo
echo "${#PAIRS[@]} unique URLs: $ok ok, $blocked bot-blocked, $dead dead"

if [ "$dead" -gt 0 ]; then
  echo "FAIL: $dead URL(s) look genuinely broken." >&2
  exit 1
fi
if [ "$STRICT" -eq 1 ] && [ "$blocked" -gt 0 ]; then
  echo "FAIL (--strict): $blocked URL(s) could not be verified." >&2
  exit 1
fi
echo "PASS (bot-blocked URLs need a human with a browser; they are not failures here)."
