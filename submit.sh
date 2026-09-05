#!/usr/bin/env bash
# Submit a set of public URLs to the Internet Archive's Save Page Now.
#
#   ./submit.sh host <host>   every <loc> in https://<host>/sitemap.xml, plus the
#                             lines of extra-urls.txt that belong to that host
#   ./submit.sh corpora       the raw URL of every tracked *.md in each repository
#                             listed in corpora.txt (minus README/TIMESTAMPS/ZENODO)
#
# DRY_RUN=1 lists what would be submitted and touches nothing.
#
# The loop is the same one every site repo's snapshot.yml runs on push: ~12 s
# between requests (Save Page Now rate-limits), 30 s per request. The response
# code is a heuristic — a 404 has accompanied a successful capture — so the
# authoritative check is the CDX API, never this log.
#
# With IA_S3_ACCESS_KEY and IA_S3_SECRET_KEY in the environment it uses the Save
# Page Now 2 API instead: authenticated, asynchronous (a job id comes back at
# once), and with if_not_archived_within (IA_IF_NOT_ARCHIVED_WITHIN, default 20h)
# so a page captured earlier the same day is not captured again. The key pair is
# checked against the status endpoint first; a rejected pair falls back to the
# anonymous path with a warning rather than failing every request.
set -uo pipefail
KIND="${1:-}"; ARG="${2:-}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
UA='HeartBank-snapshot-bot (+https://github.com/333eco/snapshot.333.eco)'
urls=()

case "$KIND" in
  host)
    HOST="$ARG"
    [ -n "$HOST" ] || { echo "usage: $0 host <host>"; exit 2; }
    SM="$(curl -sS -L -m 60 -A "$UA" "https://${HOST}/sitemap.xml" || true)"
    if [ -z "$SM" ]; then
      echo "::warning::${HOST}: sitemap.xml not reachable — only extra-urls.txt entries will be submitted"
    fi
    while IFS= read -r u; do [ -n "$u" ] && urls+=("$u"); done < <(
      printf '%s' "$SM" | grep -oE '<loc>[^<]+</loc>' | sed -E 's|</?loc>||g; s/^[[:space:]]+//; s/[[:space:]]+$//')
    while IFS= read -r u; do [ -n "$u" ] && urls+=("$u"); done < <(
      sed 's/#.*//' extra-urls.txt | tr -d ' \t' | grep -E "^https?://${HOST}(/|$)" || true)
    LABEL="$HOST"
    ;;
  corpora)
    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      dir="$(mktemp -d)"
      if git clone --quiet --depth 1 "https://github.com/${repo}.git" "$dir" 2>/dev/null; then
        branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD)"
        while IFS= read -r f; do
          urls+=("https://raw.githubusercontent.com/${repo}/${branch}/${f}")
        done < <(git -C "$dir" ls-files '*.md' | grep -vE '(^|/)(README|TIMESTAMPS|ZENODO)\.md$' | sort)
      else
        echo "::warning::could not clone ${repo}"
      fi
      rm -rf "$dir"
    done < <(sed 's/#.*//' corpora.txt | tr -d ' \t' | grep -v '^$')
    LABEL="corpora"
    ;;
  *)
    echo "usage: $0 host <host> | corpora"; exit 2 ;;
esac

# Dedupe, preserving order.
uniq_urls="$(printf '%s\n' ${urls[@]+"${urls[@]}"} | awk 'NF && !seen[$0]++')"
total="$(printf '%s\n' "$uniq_urls" | grep -c . || true)"

{
  echo "## Daily full snapshot — \`$LABEL\` — $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo ""
  echo "**$total** URL(s). Internet Archive submitted automatically; **archive.today** is a browser leg — the estate runs it with the \`/snapshot\` skill over the CORPUS papers, and the per-URL links below cover anything else."
  echo "The response code is a heuristic; the authoritative check is the CDX API."
  echo ""
} >> "$SUMMARY"

# ---- Which Save Page Now: authenticated SPN2 when the key pair is present, else anonymous.
AUTH=""
PATH_NOTE="anonymous Save Page Now (set IA_S3_ACCESS_KEY / IA_S3_SECRET_KEY for SPN2)"
if [ -n "${IA_S3_ACCESS_KEY:-}" ] && [ -n "${IA_S3_SECRET_KEY:-}" ] && [ -z "${DRY_RUN:-}" ]; then
  AUTH="LOW ${IA_S3_ACCESS_KEY}:${IA_S3_SECRET_KEY}"
  # A bad or expired pair must degrade visibly, not fail once per URL: ask the status endpoint first.
  quota="$(curl -sS -m 30 -H 'Accept: application/json' -H "Authorization: $AUTH" -A "$UA" \
    https://web.archive.org/save/status/user 2>/dev/null || true)"
  if printf '%s' "$quota" | jq -e '.available != null' >/dev/null 2>&1; then
    PATH_NOTE="SPN2, authenticated · quota $(printf '%s' "$quota" | jq -c '{available,processing,daily_captures,daily_captures_limit}')"
  else
    echo "::warning::IA_S3 key pair is set but the SPN2 status endpoint did not accept it (${quota:0:120}); using anonymous Save Page Now"
    AUTH=""
    PATH_NOTE="anonymous Save Page Now (the IA_S3 key pair was REJECTED — check the secrets)"
  fi
fi
echo "Path: $PATH_NOTE"
echo "_Path: ${PATH_NOTE}_" >> "$SUMMARY"
echo "" >> "$SUMMARY"

submitted=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  enc="$(jq -rn --arg u "$url" '$u|@uri')"
  echo "Submitting to Internet Archive: $url"
  if [ -n "${DRY_RUN:-}" ]; then
    result="DRY"
  elif [ -n "$AUTH" ]; then
    # One account, a handful of concurrent capture slots (the status endpoint said
    # "available": 3 on the first run), shared by EVERY job of this workflow — the
    # matrix no longer buys throughput the way it did per-IP anonymously. So: wait
    # for a free slot (bounded), then submit; and if the API still reports the
    # session limit (a parallel job took the slot between the poll and the POST),
    # back off and retry a few times rather than losing the URL for the day.
    attempt=0
    while :; do
      waited=0
      while [ "$waited" -lt 180 ]; do
        avail="$(curl -s -m 20 -H 'Accept: application/json' -H "Authorization: $AUTH" -A "$UA" \
          https://web.archive.org/save/status/user 2>/dev/null | jq -r '.available // 1' 2>/dev/null || echo 1)"
        [ "${avail:-1}" != "0" ] && break
        [ "$waited" -eq 0 ] && echo "  waiting for a free SPN2 slot…"
        sleep 10; waited=$((waited + 10))
      done
      resp="$(curl -s -m 30 -X POST -H 'Accept: application/json' -H "Authorization: $AUTH" -A "$UA" \
        --data-urlencode "url=$url" \
        --data-urlencode "if_not_archived_within=${IA_IF_NOT_ARCHIVED_WITHIN:-20h}" \
        https://web.archive.org/save || true)"
      if printf '%s' "$resp" | grep -qiE 'user-session-limit|limit of active sessions' && [ "$attempt" -lt 6 ]; then
        attempt=$((attempt + 1))
        echo "  SPN2 session limit reached; retry $attempt of 6 in 20 s"
        sleep 20
        continue
      fi
      break
    done
    if printf '%s' "$resp" | jq -e '.job_id' >/dev/null 2>&1; then
      result="queued $(printf '%s' "$resp" | jq -r '.job_id')"
      msg="$(printf '%s' "$resp" | jq -r '.message // empty')"
      [ -n "$msg" ] && result="$result — $msg"
    else
      msg="$(printf '%s' "$resp" | jq -r '.message // .status_ext // empty' 2>/dev/null || true)"
      result="error: ${msg:-${resp:0:160}}"
      [ -n "$resp" ] || result="error: no response"
    fi
  else
    code="$(curl -s -L -m 30 -o /dev/null -w '%{http_code}' -A "$UA" \
      "https://web.archive.org/save/$url")"
    result="HTTP ${code:-000}"   # a timeout already prints 000; never double it
  fi
  echo "  Internet Archive: $result"
  submitted=$((submitted + 1))
  {
    echo "### \`$url\`"
    echo ""
    echo "- 🗄️ **Internet Archive** — $result · [view captures](https://web.archive.org/web/*/$url)"
    echo "- 📎 **archive.today** — *click to capture:* https://archive.ph/?url=$enc"
    echo ""
  } >> "$SUMMARY"
  [ -n "${DRY_RUN:-}" ] || sleep 12
done <<< "$uniq_urls"

echo "" >> "$SUMMARY"
echo "_Submitted $submitted of $total for \`$LABEL\`._" >> "$SUMMARY"
echo "Done ($LABEL): submitted $submitted of $total."
