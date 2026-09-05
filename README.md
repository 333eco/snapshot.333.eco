# snapshot.333.eco

The estate's weekly Internet Archive refresh, run from one public repository for
every site and both public corpora. It is the Sunday half of the prior-art
snapshot; the push half stays in each site repository.

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
| `extra-urls.txt` | what cannot be derived — redirect URLs and pages kept out of a sitemap |

Nothing derivable is hand-listed. The live sitemap is the set of public routes
and can be ahead of any checkout; the corpus tree is the set of papers and the
hand-kept manifests were twelve papers behind it on the day this replaced them.

## How drift is caught

Each site repository's `snapshot.yml` checks on every push that its host is in
`hosts.txt` and that every URL in its `snapshot-urls.txt` is either in its
sitemap, under a listed corpus, or in `extra-urls.txt`. A URL that is in none of
those would be archived by nobody, and the check turns *that* repository's run
red. This repository is public, so the check needs no token; if it cannot be
fetched the check warns and does not fail.

## Adding a site

Add the host to `hosts.txt`. If a URL of that site must be archived but is not
in its sitemap, add it to `extra-urls.txt`. Push. The next Sunday covers it; to
cover it now, run the workflow by hand with the host as input.

## Running by hand

**Actions → Weekly full snapshot → Run workflow.** Leave `host` blank for
everything, or name one host; untick `corpora` to skip the corpus sources.
`./submit.sh host thonly.org` and `./submit.sh corpora` run the same code
locally, and `DRY_RUN=1` lists what would be submitted without submitting.

## Honest limits

- The submit response code is a heuristic. A 404 has accompanied a successful
  capture. The authoritative check is the CDX API:
  `https://web.archive.org/cdx/search/cdx?url=<URL>&output=json&fl=timestamp,statuscode`
- Save Page Now renders a single-page app's route and metadata at a timestamp;
  imperfect SPA fidelity is an accepted prior-art limitation. For a redirect it
  records the 301, which is what keeps a renamed paper's citations stable.
- archive.today and perma.cc resist automation; each job summary carries
  prefilled links for them, and that click is the only manual step.
- `LAST-RUN.md` is rewritten and committed by every run. GitHub pauses a
  scheduled workflow after 60 days without repository activity, and that commit
  is the activity. Do not delete the step to keep the history tidy.
