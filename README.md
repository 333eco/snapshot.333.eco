# snapshot.333.eco

The estate's daily Internet Archive refresh, run from one public repository for
every site and both public corpora, and its second custodian: Software Heritage,
which keeps the public corpus repositories with their whole history. It is the
full-refresh half of the prior-art snapshot; the push half stays in each site
repository.

**Public on purpose.** Nothing here is secret — every URL is being sent to a
public archive, each sitemap is public, the corpora are public, and Save Page
Now takes no credential. What being public buys is the reason this repository
exists: GitHub Actions minutes bill the owner of a *private* repository, and the
same Sunday job spread across 22 private repositories cost about 580 minutes a
month, most of it a runner sleeping between rate-limited requests. Here it costs
nothing. That is a property of where the job runs, not a budget anyone has to
watch.

## Why it is on 333.eco

The same argument that placed B-Registry℠, the brand layer and the corpus
server here: this serves four GitHub organisations and two dozen hosts, and
filing it under any one body's domain would make that body the custodian of the
others' record. There is no `snapshot.333.eco` host; the name follows the
estate's convention for institution-wide repositories, as `shared.333.eco` does.

## What it reads

| file | what the run does with it |
|---|---|
| `hosts.txt` | fetches `https://<host>/sitemap.xml` **live** and submits every `<loc>` |
| `corpora.txt` | clones each public corpus repository and submits the raw URL of every tracked `*.md` except `README.md`, `TIMESTAMPS.md`, `ZENODO.md` |
| `extra-urls.txt` | what cannot be derived — pages kept out of a sitemap (not redirects; see the file's header) |
| `heritage.txt` | the public corpus repositories Software Heritage keeps — see below |

Nothing derivable is hand-listed. The live sitemap is the set of public routes
and can be ahead of any checkout; the corpus tree is the set of papers and the
hand-kept manifests were twelve papers behind it on the day this replaced them.

## Cadence

Daily, 06:00 UTC — raised from weekly on 2026-09-05, because the run is free
here. What the cadence buys is the corpus: a paper revised in the publications
repositories is captured by no push job (those repositories have none), so its
Wayback lag was up to seven days and is now one. Not every other day: `*/2` in
cron is day-of-month arithmetic and skips a beat at every 31-day month; daily is
a property, every-other-day is a rule with an exception. The Archive stores an
unchanged page as a revisit record, so what a daily request for an unchanged URL
costs it is the request.

## Software Heritage — the second custodian

Ruled 2026-10-01. Until then every third-party copy of the corpus sat with one
organisation, and the Internet Archive answered *"Temporarily Offline"* in the
middle of the check that led to the ruling. archive.today had been meant as the
second copy, but it resists automation by design and stood at 2 captures of 232.

`heritage.sh` reads each repository in `heritage.txt`, compares GitHub's head
with the head that Software Heritage's latest snapshot holds, and files a
[Save Code Now](https://archive.softwareheritage.org/save/) request only when
they differ — so an unchanged repository costs Software Heritage nothing. A save
counts only when the new snapshot's default branch points at the commit that was
asked for. The API is anonymous: no secret, no CAPTCHA, no person.

One save covers every revision of every file, because the archive takes the git
history. What it dates is its own visit; commit dates inside git are written by
the committer and prove nothing alone. A paper may point at its repository's
origin page — `https://archive.softwareheritage.org/browse/origin/?origin_url=https://github.com/<repo>`
— but never at the identifier of a snapshot that contains the paper itself: the
identifier cannot exist until the paper does, which is the same loop that ruled
`sha256:` out of front matter.

## The archive.org key (optional)

Two repository secrets, `IA_S3_ACCESS_KEY` and `IA_S3_SECRET_KEY` — an
archive.org account's S3-style pair from <https://archive.org/account/s3.php>.
Set them without the value ever passing through a chat or a shell history:

```
gh secret set IA_S3_ACCESS_KEY -R 333eco/snapshot.333.eco   # prompts; paste
gh secret set IA_S3_SECRET_KEY -R 333eco/snapshot.333.eco
```

With them, `submit.sh` uses the Save Page Now 2 API: authenticated,
asynchronous (a job id comes back at once instead of a held connection), and
with `if_not_archived_within=20h` so a page a push captured earlier the same day
is not captured twice. Without them it uses anonymous Save Page Now, exactly as
before. A pair that is set but rejected degrades to anonymous with a warning,
never to an error per URL, and every job summary opens with which path ran and
the account's quota (`available` concurrent slots, `daily_captures_limit`).
Those slots are per account and shared by every job of a run, so `submit.sh`
waits for a free one before each request and retries on the session-limit
error; the matrix runs at most three hosts at a time for the same reason.

The key lives only here. The site repositories' push jobs are secret-free by
design; this repository has no `pull_request` trigger, so a fork cannot reach
the secret; and the estate's session archives carry prompts verbatim, which is
why a credential must never be pasted into a conversation.

## How drift is caught

Each site repository's `snapshot.yml` checks on every push that its host is in
`hosts.txt` and that every URL in its `snapshot-urls.txt` is either in its
sitemap, under a listed corpus, or in `extra-urls.txt`. A URL that is in none of
those would be archived by nobody, and the check turns *that* repository's run
red. This repository is public, so the check needs no token; if it cannot be
fetched the check warns and does not fail.

## Adding a site

Add the host to `hosts.txt`. If a URL of that site must be archived but is not
in its sitemap, add it to `extra-urls.txt`. Push. The next morning covers it; to
cover it now, run the workflow by hand with the host as input.

## Running by hand

**Actions → Daily full snapshot → Run workflow.** Leave `host` blank for
everything, or name one host; untick `corpora` to skip the corpus sources.
`./submit.sh host thonly.org` and `./submit.sh corpora` run the same code
locally, and `DRY_RUN=1` lists what would be submitted without submitting.

## Honest limits

- The submit response code is a heuristic. A 404 has accompanied a successful
  capture. The authoritative check is the CDX API:
  `https://web.archive.org/cdx/search/cdx?url=<URL>&output=json&fl=timestamp,statuscode`
- Our routes are prerendered, so what Save Page Now stores for a route already
  holds the text: measured 2026-10-01 on two papers, the stored HTML carried the
  full body, the DOI and the licence. The *replay* was measured the same day on
  seven pages (papers, landing pages, a static letter, a raw markdown file): all
  seven rendered in full, and every resource came from archive.org — none from
  our live sites. Desktop Chrome only; mobile was not tested.
- For a redirect it follows the hop and records the **target**. The 301 row that
  joins an old URL to a new one was recorded on first submission (June 2026 for
  the heartbank.net research mirror) and never again, so a rename is captured
  once, the day it ships — confirm the 301 row in the CDX and do not list the
  old URL in `extra-urls.txt`.
- **archive.today was retired as a leg on 2026-10-01.** It resists automation
  (`curl` gets a `429`, Chrome a Cloudflare check a person must clear) and its one
  advantage — rendering the app — buys nothing on prerendered routes. The
  `/snapshot` skill still exists for a one-off capture, and `archive-today.tsv`
  records the few there are; it is a cache, and `https://archive.ph/newest/<url>`
  is authoritative. Papers that still advertise an archive.today mirror are
  corrected as each is revised, the same way as the perma.cc lines.
- **perma.cc was ruled out of the estate on 2026-09-05.** Its free tier is ten links
  on a one-time trial, not ten a month, after which an individual must pay or be
  affiliated with a registrar; ten cannot mirror 136 papers. Papers that still
  advertise a perma.cc mirror are wrong and are corrected as each is revised.
- `LAST-RUN.md` is rewritten and committed by every run. GitHub pauses a
  scheduled workflow after 60 days without repository activity, and that commit
  is the activity. Do not delete the step to keep the history tidy.
