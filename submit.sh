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
  echo "## Weekly full snapshot — \`$LABEL\` — $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo ""
  echo "**$total** URL(s). Internet Archive submitted automatically; **archive.today** and **perma.cc** are manual — links per URL below."
  echo "The response code is a heuristic; the authoritative check is the CDX API."
  echo ""
} >> "$SUMMARY"

submitted=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  enc="$(jq -rn --arg u "$url" '$u|@uri')"
  echo "Submitting to Internet Archive: $url"
  if [ -n "${DRY_RUN:-}" ]; then
    code=DRY
  else
    code="$(curl -s -L -m 30 -o /dev/null -w '%{http_code}' -A "$UA" \
      "https://web.archive.org/save/$url")"
    code="${code:-000}"   # a timeout already prints 000; never double it
  fi
  echo "  Internet Archive HTTP $code"
  submitted=$((submitted + 1))
  {
    echo "### \`$url\`"
    echo ""
    echo "- 🗄️ **Internet Archive** — submitted (HTTP $code) · [view captures](https://web.archive.org/web/*/$url)"
    echo "- 📎 **archive.today** — *click to capture:* https://archive.ph/?url=$enc"
    echo "- ⚖️ **perma.cc** — *capture manually at* https://perma.cc/ · paste: \`$url\`"
    echo ""
  } >> "$SUMMARY"
  [ -n "${DRY_RUN:-}" ] || sleep 12
done <<< "$uniq_urls"

echo "" >> "$SUMMARY"
echo "_Submitted $submitted of $total for \`$LABEL\`._" >> "$SUMMARY"
echo "Done ($LABEL): submitted $submitted of $total."
