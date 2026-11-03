#!/usr/bin/env bash
# Keep each repository in heritage.txt archived by Software Heritage.
#
#   ./heritage.sh            check every origin; save the ones whose head moved
#   DRY_RUN=1 ./heritage.sh  report what is held and what would be saved
#
# For each repository: read GitHub's head of the default branch, read the head
# Software Heritage's latest full snapshot holds, and file a Save Code Now
# request only when the two differ. A save counts only when its snapshot's
# default branch points at the commit that was asked for — the job's own
# success flag is not the evidence, the snapshot is.
#
# Software Heritage keeps the whole git history, so one save covers every
# revision of every file. What it dates is its own VISIT; the commit dates inside
# git are self-reported and prove nothing alone.
#
# Exit 1 if any save failed, a public check failed outright, or an origin has had
# no successful save for HERITAGE_STALL_DAYS, so the run turns red and LAST-RUN.md
# says so. Two things are warnings, not failures, because the next run takes them:
# a head that moved again during the save, and a save still in Software Heritage's
# queue when this job stops waiting. Their queue is theirs: request 2575360 ended
# 'succeeded' five minutes after a 20-minute wait called it a failure (2026-10-25),
# and a request of 2026-10-26 took over two hours, past the job's own timeout.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # a missing or private repo must fail, never wait for a password
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
API='https://archive.softwareheritage.org/api/1'
UA='HeartBank-snapshot-bot (+https://github.com/333eco/snapshot.333.eco)'
POLL="${HERITAGE_POLL_SECONDS:-30}"
# One budget for ALL the waits, kept under the job's timeout-minutes in snapshot.yml.
# Per save, ten queued requests could outlast the job and get it cancelled.
WAIT="${HERITAGE_WAIT_SECONDS:-3600}"
STALL_DAYS="${HERITAGE_STALL_DAYS:-21}"   # three weekly runs
fail=0

get() { curl -sS -m 60 -A "$UA" "$@"; }

# The commit the latest full snapshot of an origin holds for refs/heads/<branch>.
held_head() {
  local origin="$1" branch="$2" visit snp
  visit="$(get "${API}/origin/${origin}/visit/latest/?require_snapshot=true" || true)"
  snp="$(printf '%s' "$visit" | jq -r '.snapshot // empty' 2>/dev/null || true)"
  [ -n "$snp" ] || return 0
  get "${API}/snapshot/${snp}/" 2>/dev/null \
    | jq -r --arg b "refs/heads/${branch}" '.branches[$b].target // empty' 2>/dev/null || true
}

{
  echo "## Software Heritage"
  echo ""
  echo "| repository | GitHub head | held before | action | snapshot |"
  echo "|---|---|---|---|---|"
} >> "$SUMMARY"

declare -a pending_repo pending_id pending_head pending_branch
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  origin="https://github.com/${repo}"
  branch="$(get "https://api.github.com/repos/${repo}" | jq -r '.default_branch // empty' 2>/dev/null || true)"
  [ -n "$branch" ] || branch=main
  head="$(git ls-remote "$origin" "refs/heads/${branch}" 2>/dev/null | cut -f1)"
  if [ -z "$head" ]; then
    echo "::error::${repo}: could not read the head of ${branch} — is the repository still public?"
    echo "| \`${repo}\` | — | — | ❌ head unreadable | — |" >> "$SUMMARY"
    fail=1; continue
  fi
  held="$(held_head "$origin" "$branch")"
  if [ "$held" = "$head" ]; then
    echo "${repo}: already held at ${head:0:7}"
    echo "| \`${repo}\` | \`${head:0:7}\` | \`${held:0:7}\` | ✅ already held | — |" >> "$SUMMARY"
    continue
  fi
  if [ -n "${DRY_RUN:-}" ]; then
    echo "${repo}: would save (GitHub ${head:0:7}, held ${held:0:7})"
    echo "| \`${repo}\` | \`${head:0:7}\` | \`${held:0:7}\` | would save | — |" >> "$SUMMARY"
    continue
  fi
  resp="$(get -X POST "${API}/origin/save/git/url/${origin}/" || true)"
  id="$(printf '%s' "$resp" | jq -r '.id // empty' 2>/dev/null || true)"
  status="$(printf '%s' "$resp" | jq -r '.save_request_status // empty' 2>/dev/null || true)"
  if [ -z "$id" ] || [ "$status" = "rejected" ]; then
    echo "::error::${repo}: save request not accepted: ${resp:0:300}"
    echo "| \`${repo}\` | \`${head:0:7}\` | \`${held:0:7}\` | ❌ request not accepted | — |" >> "$SUMMARY"
    fail=1; continue
  fi
  echo "${repo}: save request ${id} ${status} (GitHub ${head:0:7}, held ${held:0:7})"
  pending_repo+=("$repo"); pending_id+=("$id"); pending_head+=("$head"); pending_branch+=("$branch")
done < <(sed 's/#.*//' heritage.txt | tr -d ' \t' | grep -v '^$')

# Days since this origin's last successful save, empty if none is on record.
days_since_success() {
  get "${API}/origin/save/git/url/$1/" 2>/dev/null | jq -r '
    [.[] | select(.save_task_status == "succeeded") | .save_request_date | .[0:19] + "Z" | fromdate]
    | if length == 0 then empty else ((now - max) / 86400 | floor) end' 2>/dev/null || true
}

# Wait for every accepted request, then check what each snapshot actually holds.
deadline=$((SECONDS + WAIT))
for i in "${!pending_id[@]}"; do
  repo="${pending_repo[$i]}"; id="${pending_id[$i]}"; head="${pending_head[$i]}"; branch="${pending_branch[$i]}"
  task=""; snp=""
  while :; do   # always at least one read, however little budget is left
    r="$(get "${API}/origin/save/${id}/" || true)"
    task="$(printf '%s' "$r" | jq -r '.save_task_status // empty' 2>/dev/null || true)"
    case "$task" in succeeded|failed) break ;; esac
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep "$POLL"
  done
  if [ -n "$task" ] && [ "$task" != "succeeded" ] && [ "$task" != "failed" ]; then
    age="$(days_since_success "https://github.com/${repo}")"
    if [ -n "$age" ] && [ "$age" -lt "$STALL_DAYS" ]; then
      echo "::warning::${repo}: save ${id} still '${task}' in Software Heritage's queue when the wait ended; last success ${age} days ago; the next run checks it"
      echo "| \`${repo}\` | \`${head:0:7}\` | — | ⏳ still ${task} (request ${id}) | — |" >> "$SUMMARY"
      continue
    fi
    echo "::error::${repo}: save ${id} still '${task}', and no successful save in ${age:-any recorded} days (limit ${STALL_DAYS})"
    echo "| \`${repo}\` | \`${head:0:7}\` | — | ❌ stalled: ${task} (request ${id}) | — |" >> "$SUMMARY"
    fail=1; continue
  fi
  if [ "$task" != "succeeded" ]; then
    echo "::error::${repo}: save ${id} ended '${task:-unknown}'"
    echo "| \`${repo}\` | \`${head:0:7}\` | — | ❌ save ${task:-timed out} (request ${id}) | — |" >> "$SUMMARY"
    fail=1; continue
  fi
  snp="$(printf '%s' "$r" | jq -r '.snapshot_swhid // empty' 2>/dev/null || true)"
  got="$(get "${API}/snapshot/${snp##*:}/" 2>/dev/null \
    | jq -r --arg b "refs/heads/${branch}" '.branches[$b].target // empty' 2>/dev/null || true)"
  if [ "$got" = "$head" ]; then
    echo "${repo}: saved ${head:0:7} → ${snp}"
    echo "| \`${repo}\` | \`${head:0:7}\` | — | ✅ saved, head verified | \`${snp}\` |" >> "$SUMMARY"
  else
    echo "::warning::${repo}: snapshot ${snp} holds ${got:0:7}, not ${head:0:7} — the head moved during the save; the next run takes it"
    echo "| \`${repo}\` | \`${head:0:7}\` | — | ⚠️ saved \`${got:0:7}\`, head moved | \`${snp}\` |" >> "$SUMMARY"
  fi
done

exit "$fail"
