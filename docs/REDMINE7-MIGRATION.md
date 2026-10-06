# Redmine 7 migration: redmine_extended_api

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL and MariaDB, every function exercised end to end on a real running Redmine in a
> browser (with and without permissions, failure paths included) with screenshots you looked at,
> and an OpenAI review of the diff when OPENAI_API_KEY is set. Report to me in Dutch at the end.

This file is the plan and the memory of that work. Update it as you go: verdicts, results,
what is left. Written 2026-10-06 from a measured analysis (report at the bottom).

## Status

| | |
|---|---|
| Plugin id | `redmine_extended_api` |
| GEOxyz runs today | `main` |
| Upstream | geen |
| Runs on Redmine 7 as is | DEELS (before this branch); JA on this branch |
| Upstream sync | GEEN UPSTREAM |
| After sync | n.v.t. |
| Complexity (1 trivial .. 5 rewrite) | 2 |
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 and MariaDB 10.11 |
| Branch head when this file was written | `fed0232` |
| Migration session finished | 2026-10-06, all work list items done, see "Results" |

## Already on this branch

All runs on 7.0-stable-GEOxyz (Redmine 7.0.1, Rails 8.1.3.1, Ruby 3.3.6) unless said otherwise. Every fix
has a test that fails without it; all of them also run on 5.1-stable.

| commit | what | found by |
|---|---|---|
| `431e985` | Issue overrides (author_id, created_on, updated_on, closed_on) on create were silently lost on Rails 7.1+: `update_columns` adds the stale in-memory `lock_version` to its WHERE. Now `where(id:).update_all` (the Rails 6.1 behaviour). Spec fake updated. | analysis, work list 1-2 |
| `c5b38d3` | Test: Redmine 7 webhooks carry the imported author/dates, equal to what is stored. | work list 5 |
| `8378146` | DELETE of an issue status in use: 422 with core's message instead of 500 (`check_integrity` raises). | e2e |
| `e5add4c` | Refused deletes (tracker/role in use, custom field) came back as an empty 422 (`render_error` answers API formats with `head`); now `{"errors":[reason]}`. | e2e |
| `94c5744` | Custom field create without a valid `type`: 422 `Type is invalid` instead of 200 with core's HTML type picker. | e2e |
| `f175456` | Override values that cannot be stored (unparseable time, unknown user id) are refused with 422 before anything is saved. Before: issue/attachment saved with created_on NULL, journal 500, and on Redmine 7 a 500 from the webhook payload after the issue was committed. | e2e |
| `8b18fc3` | notify=false used `Mailer.with_deliveries(false)`, which switches mail off for the whole process: mail of other requests/async jobs delivered meanwhile was lost (seen in the e2e run). Replaced by a thread-local mail interceptor. | e2e |
| `6704885` | Issue update without changes: 204 like core, not 200 with a journal without id. | e2e |
| `900d3f2` | Proxy dropped the parsed form but left `rack.request.form_input`: every form encoded POST/PUT through /extended_api was a 500 on Redmine 5.1 (Rack 2). JSON was fine. | tests on 5.1 |
| `1df0d59`, `7d3dee7` | Test kit: PostgreSQL provisioning as root; file mail delivery only for the server env (it leaked into the test env and made "no mail" tests pass vacuously). | setup |
| `c49144c`, `b79769a`, `bf7bc7c` | Tests run on 5.1 too; tolerate plugins that widen core permissions (redmine_editauthor); review fix. | 5.1 run, together run, OpenAI review |
| `4c7729a`, `22c630d` | End to end scenarios (test/e2e) and screenshots (docs/e2e). | |

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Priority items**

1. Fix lib/redmine_extended_api/patches/issue_patch.rb:99 (update_columns + lock_version on Rails 8 loses author_id/created_on overrides) together with its spec. **DONE** `431e985` (integration test fails without it on 7.0; spec fake now records `where(id:).update_all`).

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

2. lib/redmine_extended_api/patches/issue_patch.rb:99 update_columns -> update_all (of lock_version herladen) zodat author_id/created_on-overrides bij issue-create weer werken; spec/issue_patch_spec.rb mee aanpassen. **DONE** with item 1 (`update_all`); curl/e2e: issue-overrides scenario.
3. Issue-update met updated_on/closed_on-override testen op R7. **DONE**: worked already on R7 (no lock_version conflict on update); covered by `test_update_issue_as_admin_persists_updated_on_and_closed_on`, a second update after an override (optimistic locking intact) and the e2e screenshot `issue-overrides-admin-update`.

**Checks**

4. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL AND MariaDB, and once on 5.1-stable if the branch is meant to stay 5.1-compatible. **DONE**, numbers under "Results".
5. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed. **DONE**: the issue payload is rendered in `after_*_commit`, after the plugin's `after_save` wrote the overrides, so `issue.created`/`issue.updated` carry the imported author and dates, equal to the database (integration test + real webhook received in the e2e run, screenshot `issue-overrides-webhook-payloads`). An unparseable override date used to make the webhook payload raise (500 after commit): fixed by `f175456`. notify=false does not suppress webhooks (mail only): see open question 2.
6. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots). **DONE**, see "Inventory of functions".

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- No migrations, no settings, no files. Deploy the branch and restart.
- Behaviour changes API clients may notice (all on `/extended_api`, all fixes): an admin override with a
  value that cannot be stored now answers 422 (`"Created is invalid"`, `"Author is invalid"`) instead of
  saving NULL/dangling data; refused deletes now carry the reason in `errors`; a custom field create
  without `type` answers 422 instead of HTML; an issue update without changes answers 204 like core.
- If an import ran with garbage dates before, look for broken rows:
  `Issue.where(created_on: nil)`, `Attachment.where(created_on: nil)`, issues/journals whose
  author_id/user_id has no user.
- REST API stays required (Administration > Settings > **Integrations** on Redmine 7, the tab was "API").

## Results (2026-10-06)

| run | result |
|---|---|
| tests, 7.0-stable-GEOxyz, PostgreSQL 16.15 | minitest 25 runs, 108 assertions, 0 failures; rspec 157 examples, 0 failures |
| tests, 7.0-stable-GEOxyz, MariaDB 10.11.14 | minitest 25 runs, 108 assertions, 0 failures; rspec 157 examples, 0 failures |
| tests, 5.1-stable, PostgreSQL, Ruby 3.2.6 | minitest 25 runs, 0 failures, 1 skip (webhook test: no webhooks before 7.0); rspec 157 examples, 0 failures |
| baseline before changes (7.0, PostgreSQL) | rspec 147 examples, 0 failures (all doubles: the update_columns bug was invisible to them) |
| e2e, PostgreSQL, production mode | smoke + core + 11 scenarios, 78 screenshots, 0 problems (`docs/e2e/`) |
| e2e, MariaDB, production mode | same set, 78 screenshots, 0 problems (not committed, identical captions) |
| together with redmine_depending_custom_fields, redmine_view_issue_description, redmine_itil_priority, redmine_editauthor (their redmine70-migration branches), PostgreSQL | tests green after `b79769a`; e2e: no failure caused by this plugin. Differences are the other plugins' features and equal on core and extended paths: with redmine_editauthor a non-admin with its permission (and the core path) sets `author_id` (created_on stays ignored); with redmine_view_issue_description the reporter/outsider get 403 on `/issues/1` (kit core flow) and on notes. |
| migrations up/down | n.v.t.: the plugin has no migrations. Boot and eager load: production server started on both databases. |
| OpenAI review | `docs/reviews/openai-2026-10-06-b79769a.md`: 6 findings, 1 fixed (`bf7bc7c`), 5 refuted with a resolution each; second run `openai-2026-10-06-a236ea9.md`: no findings |

## Inventory of functions

The plugin has no pages, menus, permissions, settings, hooks, macros, mail handlers, rake tasks or
cron; every function is a REST endpoint under `/extended_api` (init.rb, config/routes.rb, patches).
Each scenario calls the API through the browser context as the seeded users and screenshots the
exchange and the Redmine page that shows the result.

| function | how a user reaches it | scenario | screenshots (docs/e2e) |
|---|---|---|---|
| Proxy: every core REST endpoint under `/extended_api`, `x-redmine-extended-api: native`, HTML routes 404, REST API setting respected | any API client | `test/e2e/proxy.mjs` | proxy-rest-api-on, -same-as-core, -permissions, -not-api, -rest-api-off, -rest-api-off-refused |
| Issue statuses show/create/update/delete (extended only) | admin API | `issue_statuses.mjs` | issue-statuses-admin-crud, -admin-list, -refused, -delete |
| Trackers show/create (copy_workflow_from)/update/delete | admin API | `trackers.mjs` | trackers-admin-crud, -admin-list, -admin-edit, -in-project, -refused, -delete |
| Roles create/update/delete (show/index core) | admin API | `roles.mjs` | roles-admin-crud, -admin-edit, -refused, -delete |
| Custom fields show/create (list, enumeration)/update/delete | admin API | `custom_fields.mjs` | custom-fields-admin-create, -admin-update, -admin-list, -admin-edit, -issue-form, -refused, -delete |
| Enumerations index by type/show/create/update/delete with reassign_to_id | admin API (index for all API users) | `enumerations.mjs` | enumerations-admin-crud, -admin-list, -refused, -reassign |
| Issue overrides author_id/created_on/updated_on/closed_on, Redmine 7 webhooks | admin API, ignored for others and on the core path | `issue_overrides.mjs` | issue-overrides-webhook, -admin-create, -admin-create-page, -admin-update, -admin-update-page, -webhook-payloads, -ignored, -manager-page, -refused |
| Journal overrides user_id/created_on/updated_on/updated_by_id, journal payload in the answer | admin API | `journal_overrides.mjs` | journal-overrides-admin, -history, -ignored, -history-member |
| Attachment overrides author_id/created_on on `/extended_api/uploads` | admin API | `attachment_overrides.mjs` | attachment-overrides-admin, -issue-page, -ignored, -refused, -issue-page-member |
| notify=false / send_notification=0 on issues and relations | any API user | `notifications.mjs` | notifications-calls, -mail-count, -quiet-issue |
| Issue relations create/delete (core permissions, notify=false) | members with manage_issue_relations | `relations.mjs` | relations-create, -issue-page, -refused, -delete, -issue-page-after |
| Show routes only under `/extended_api` (core `/trackers/1.json` etc. 404) | API | in the scenarios above and `smoke.mjs` | smoke-13..15, the -refused screenshots |

Users per scenario: admin (everything), manager (all project permissions, not admin: admin endpoints
403, overrides ignored), reporter (core Reporter role: 403 where core refuses), outsider (no membership:
private project refused), anonymous (401). "Before" pictures on 5.1 were not made: the plugin has no
layout, and the behaviour differences are shown by the tests that fail without each fix.

## Observations not fixed (minor, behaviour as on 5.1)

- An imported journal with only `created_on` gets `updated_on` = now, so Redmine shows it as "Edited"
  (screenshot journal-overrides-history). Sending `updated_on` too avoids it.
- Tracker-in-use message: `strip_tags` of core's HTML message leaves no space after the first sentence
  ("...cannot be deleted.The following projects...").
- Enumeration custom field update keeps options left out of the list (merge, not replace) and can give
  two options the same position.
- `GET /extended_api/<unknown id>.json` answers 404 without a body, like core.
- The plugin registers `accept_api_auth` for create/update/destroy on the core admin controllers, so an
  admin API key can also reach core's HTML-oriented create/update on the core paths (they redirect).
  Admin only; pre-existing; left as is.
- spec files that use Rails classes still depend on load order when run one by one
  (e.g. controller_patches_spec alone); the full suite is green.

## Open questions for Jan

1. **Override values that cannot be stored: 422 (built) or ignore silently?** Built: 422 with one error
   per bad value, nothing saved. Alternative: drop the bad value and save the rest. Recommendation: keep
   422, an import that sends garbage should know; before it silently wrote NULL dates/dangling authors.
2. **Should notify=false also suppress Redmine 7 webhooks?** Built: no, notify=false is about mail (core's
   `notify` attribute), webhooks still fire, also for imports. Alternative: skip `Webhook.trigger` during a
   notify=false request. Recommendation: leave webhooks on; integrations then see imported data too.
   If bulk imports must stay invisible to integrations, add a separate parameter rather than overload notify.
3. **Issue update without changes: 204 (built, like core) or the old 200 with an empty journal?**
   Recommendation: 204; the old answer had no id and no date and described nothing.
4. **Keep 5.1 compatibility?** The branch runs on 5.1-stable (tests green) and fixes a 500 for form encoded
   POSTs there (`900d3f2`); it could be merged into `main` before the Redmine 7 upgrade.

## Not testable here

- Nothing needs external credentials: the plugin uses Redmine's own API authentication (Basic and API
  key tested; OAuth tokens through Doorkeeper not tested, no OAuth app was set up). Mail was tested with
  file delivery, not a real SMTP server.

## How to test

```sh
./.codex/redmine_clone.sh 7.0-stable-GEOxyz      # or 5.1-stable / 6.1-stable / 7.0-stable
./.codex/test_setup.sh                                 # RMP_DB=mariadb for MariaDB, RMP_PROVISION_DB=0 if a server runs
./.codex/test_plugin.sh                                # minitest + rspec of this plugin
```

```sh
./.codex/start_server.sh       # real Redmine (production mode) with this plugin, seeded users and projects
./.codex/e2e.sh                # browser: smoke over the plugin's pages, core issue flows, test/e2e/*.mjs
./.codex/openai_review.sh      # independent OpenAI review of the diff, only when OPENAI_API_KEY is set
```
Write one scenario per function in `test/e2e/<function>.mjs` (example at the top of
`.codex/e2e/lib.mjs`); screenshots and a table per scenario land in `docs/e2e/`. Users:
`admin`, `manager` (every permission), `reporter` (no plugin permissions), `outsider` (no
membership); password `Redmine7Test!`. Needs Node with Playwright and Chromium
(`npm install -g playwright && npx playwright install --with-deps chromium`).

On GitHub the same runs by hand only: Actions > "Redmine tests (manual)" > Run workflow (tick
"e2e" for the browser run; screenshots come back as an artifact).

The coordinator's harness (`plugin-check.sh` in the migration kit, kept outside this repo) adds a
browser smoke test of every page the plugin adds and runs all GEOxyz plugins together; the
results quoted in the analysis come from it.

## How the migration session works (same for every plugin)

1. **Start**: `git fetch && git checkout redmine70-migration && git pull`. Read this whole file,
   including the analysis report at the bottom. Do not reopen decisions recorded here.
2. **Baseline, before you change anything**:
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL and with MariaDB;
   - a real running Redmine with this plugin (`./.codex/start_server.sh`) and the browser run
     (`./.codex/e2e.sh`: smoke over every page the plugin adds, plus the core issue flows).
   Write the numbers here. Something already broken now is a finding, not your regression.
3. **Inventory of functions**: list every function of the plugin in this file, in a table
   "function | how a user reaches it | scenario | screenshot". Take them from the README,
   `init.rb` (permissions, menus, settings, project modules), routes, hooks and view
   overrides, macros, mail handling, API endpoints, rake tasks and cron jobs. This table is the
   coverage list for step 8; a function that is not in it will not be tested.
4. **GEOxyz changes**: go through the table above, one item at a time. Each kept or re-made change
   is its own commit with a test that proves it. Record the verdict in the table.
5. **Work list**: then the numbered list, in order. One concern per commit.
6. **Portability**: everything must run on Redmine's supported databases (PostgreSQL,
   MySQL/MariaDB; SQLite where the plugin already supports it). Migrations must be reversible and
   are run down and up on PostgreSQL and MariaDB.
7. **Together**: run with the other GEOxyz plugins installed (the migration kit's harness, or
   `RMP_EXTRA_PLUGINS`). A failure that only appears in combination is a finding to record here.
8. **End to end, visually, every function**: on the real Redmine from `start_server.sh`
   (production mode, the way GEOxyz runs it), write one scenario per function in
   `test/e2e/<function>.mjs` with `.codex/e2e/lib.mjs` and run them with `./.codex/e2e.sh`.
   - Each function as the users that matter: `admin`, `manager` (every permission, the
     plugin's included), `reporter` (member without the plugin's permissions), `outsider`
     (no membership, private project must stay invisible).
   - The failure paths too: setting off, permission absent, empty state, invalid input, the
     value that used to raise. A refusal that is shown is evidence as much as a success.
   - One screenshot per function and per path, with a caption saying what it proves. Open
     every screenshot and look at it: a picture nobody looked at proves nothing. Commit them
     in `docs/e2e/` and list them in the inventory table.
   - Functions without a page (mail in and out, REST API, rake tasks, cron, webhooks): exercise
     them against the same running instance (mails land in `redmine/tmp/mails`, `t.mails()`
     reads them; API through `t.page.request`) and record command and result.
   - Before pictures where behaviour or layout changes: the branch GEOxyz runs today, on
     Redmine 5.1, same scenarios, `RMP_E2E_OUT=docs/e2e/before`.
   - Run the whole e2e set once on MariaDB as well (`RMP_DB=mariadb`, then `start_server.sh --reset`).
9. **Independent review**: first your own, adversarial: re-read the whole diff as if someone
   else wrote it and you are paid to reject it. Then, **when `OPENAI_API_KEY` is set in the
   session**, `./.codex/openai_review.sh`: it sends the diff of this branch to an OpenAI model
   and writes `docs/reviews/openai-<date>-<sha>.md`. Every finding gets a `Resolution:` line
   there (fixed in <commit>, with a test, or why not). Fix, re-run the tests and the e2e set,
   and run the review again until it has nothing new that you accept. Without the key: write
   "OpenAI review: skipped, no OPENAI_API_KEY" in the report; never send code anywhere else.
10. **After the upgrade**: anything the production upgrade must do for this plugin (data fixes,
    settings, cron, files, removed features) goes into the section "After the upgrade".
11. **Finish**: update "Status", the inventory and the work list in this file, push
    `redmine70-migration`, and report: what changed, test numbers on both databases, e2e
    numbers (scenarios, screenshots, problems), the review result, what is left, what needs Jan.

### Stop and ask Jan when
- a GEOxyz change would be lost or behave differently for users;
- a new gem, a new setting with user impact, or a schema change not required by Redmine 7 seems needed;
- the change would send data to an external service (the OpenAI review of the code diff is the
  one exception Jan approved, and only when the key is present);
- upstream and GEOxyz disagree on behaviour and both are defensible.

## Rules

- **Target**: Redmine 7.0-stable-GEOxyz (https://github.com/jcatrysse/redmine), Rails 8.1, Ruby 3.3+.
  Core sources for comparison: branches `5.1-stable`, `6.1-stable`, `7.0-stable`, `7.0-stable-GEOxyz`.
- **Evidence**: never report a test, lint, browser check or review as passed without having seen
  it. Quote the summary lines; list the screenshots. "Should work" is not a result, and a green
  test suite is not proof that a feature works in the browser.
- **Tests**: never skip, delete or weaken a test. A test that encodes Redmine 5 markup or
  behaviour is updated to Redmine 7, with the reason in the commit. Every fix gets a test that
  fails without it.
- **Minimal diffs** in the plugin's own style. No reformatting, no unrelated refactoring.
  Something wrong elsewhere: write it down here, do not fix it in passing.
- **Security**: authorization on every action and entry point; `safe_attributes`, never
  `to_unsafe_hash` into `update`; no SQL built from params; no secrets in logs; no `html_safe` on
  user input.
- **Webhooks (new in Redmine 7)**: core sends issue payloads (core `issues/show.api.rsb`, rendered
  as the webhook owner) to webhook endpoints, past plugin hooks and controller patches. If the
  plugin hides, adds or changes issue data, make webhooks consistent with that or record why not.
- **Redmine 7 conventions**: SVG icons through `sprite_icon` (the `icon icon-*` CSS is gone),
  Propshaft assets under `assets/` (`/assets/plugin_assets/<id>/...`), the new header and user menu,
  `ContextMenus::*Controller`, Loofah-based text formatting, Chart.js as an ES module, sudo mode
  (on by default: `t.sudo()` in a scenario). The breaker list is in the migration kit's CHECKLIST.md.
- **Locales**: keep the locales the plugin ships in sync; translate a new key by matching the
  closest existing key in the same file, not from scratch; do not add new languages.
- **5.1 compatibility**: prefer fixes that also run on Redmine 5.1 so they can be merged early;
  say so when a fix cannot.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 7.0-stable-GEOxyz with PostgreSQL and MariaDB
  (numbers in this file); boot, production-like eager load, migrations up/down OK.
- Every function in the inventory exercised end to end on a real running Redmine, with and
  without permissions and on its failure paths; `./.codex/e2e.sh` green; screenshots looked at,
  committed in `docs/e2e/` and listed.
- Review done: your own, and the OpenAI review when the key is present, every finding resolved
  in `docs/reviews/`.
- No new failure when run together with the other GEOxyz plugins.
- "After the upgrade" lists every action production needs; "Status" is current.


## Analysis report (2026-10-06, Dutch)

# redmine_extended_api
- Gebruikte branch: main @ 132fff5 (2025-12-23) - plugin id redmine_extended_api, versie 0.1.0
- Upstream: geen (eigen plugin, github.com/jcatrysse/redmine_extended_api)
- Fork t.o.v. upstream: n.v.t.
- Andere relevante branches: geen. Geen migraties. Gem: `rspec-rails` (test).

## 1. Werkt out of the box op Redmine 7?   DEELS
Harness `redmine_extended_api@origin/main` (1006-090813-s2):
- OK bundle, boot (0.1.0), eager load, plugin migrations dev+test
- OK rspec: 147 examples, 0 failures
- OK smoke: 64/64 pages+actions zonder serverfout (4 plugin routes); geen deprecation warnings

Handmatig met curl tegen de slot-server (REST API aan, admin API key):
- OK `GET /extended_api/issues.json` 200 (header `x-redmine-extended-api: native`), `GET /extended_api/projects/geoxyz-verify.json` 200, `GET /extended_api/my/page` 404 `{"error":"Not a REST API endpoint"}` (zoals bedoeld)
- OK `GET /extended_api/{issue_statuses,trackers,enumerations,roles}/1.json` 200 (de show-routes antwoorden bewust alleen onder `/extended_api`; `GET /issue_statuses/1.json` geeft 404)
- OK `POST/PATCH/DELETE /extended_api/issue_statuses` 201/200/204; `POST/DELETE /extended_api/enumerations` 201/204; `POST /extended_api/trackers` 201; `POST /extended_api/roles` 201
- OK `PUT /extended_api/issues/11.json?notify=false` met `journal[created_on]`: 200, journal-payload terug, `created_on` 2021-01-01 opgeslagen
- FAIL (stil) `POST /extended_api/issues.json?notify=false` met `issue[author_id]=2, issue[created_on]=2020-01-02...`: 201, maar in de DB staat author_id 1 en created_on = nu. Oorzaak: lib/redmine_extended_api/patches/issue_patch.rb:99 `update_columns(cols)` in een after_save. Sinds Rails 7.1 zet `update_columns` bij optimistic locking `AND lock_version = <waarde in geheugen>` in de WHERE (activerecord 8.1 locking/optimistic.rb:154 `_query_constraints_hash`). Bij een nieuw issue heeft de nested-set callback `lock_version` in de DB net verhoogd (dev log: `UPDATE "issues" SET root_id..., lock_version = COALESCE(lock_version,0)+1`, daarna `UPDATE "issues" SET author_id=2, created_on=... WHERE id=11 AND lock_version=0` -> 0 rijen). Op Redmine 5.1 (Rails 6.1) zat lock_version niet in die WHERE, dus daar werkte de import-override wel.

## 2. Upstream sync?   GEEN UPSTREAM

## 3. Werkt na sync op Redmine 7?   n.v.t.

## 4. Complexiteit en blokkers   score 2
- Blokkers (raise): geen.
- Stille breuken:
  - lib/redmine_extended_api/patches/issue_patch.rb:99 - author_id/created_on/updated_on/closed_on-overrides bij issue-create gaan stil verloren op Rails 8 (zie boven, gemeten). Mogelijke fix: `self.class.where(id: id).update_all(cols)` i.p.v. `update_columns(cols)` (gedrag van Rails 6.1). Niet doorgevoerd: spec/issue_patch_spec.rb:47-184 gebruikt een nep-object dat `update_columns` verwacht, dus de fix vraagt ook een spec-aanpassing - ontwerpkeuze voor de eigenaar. journal_patch.rb:58 en attachment_patch.rb:76 gebruiken hetzelfde patroon maar journals/attachments hebben geen `lock_version`; de journal-override werkt aantoonbaar (curl hierboven). Issue-update met `updated_on`-override: niet gemeten.
  - lib/redmine_extended_api/proxy_app.rb `not_found_response` zet `'Content-Type'` met hoofdletters; Rack 3 (Rails 8) verwacht lowercase response-headers (Rack::Lint). Puma accepteert het (curl-test OK); cosmetisch.
- Gepatchte core-methodes 5.1 vs 7.0, allemaal nog aanwezig met dezelfde signatuur: `Issue#safe_attributes=(attrs, user=User.current)`, `Issue#init_journal(user, notes="")`, `Issue#send_notification`, `Journal#send_notification` (nog `after_create_commit`), `ApplicationController#render_api_ok`, `AttachmentsController#upload`, `IssueRelationsController#create/destroy`.
- Overlap met Redmine 7 core: 6.1 heeft een OAuth2-provider (#24808) voor API-apps en 7.0 webhooks (#29664); geen van beide geeft schrijf-endpoints voor statuses/trackers/rollen/enumerations/custom fields - geen overlap.
- Pairwise (statisch): `IssuesController` ook gepatcht door redmine_view_issue_description (prepend show/edit/update + after_action op show) - andere acties. `Issue#safe_attributes=` alias - redmine_itil_priority patcht `priority_id=`, geen conflict verwacht. De extended proxy routeert naar alle core API-routes, dus ook naar API-routes van andere plugins (redmine_itil_priority `itil_priority_settings_api`, redmine_depending_custom_fields API).
- Open werk voor ansif:
  - issue_patch.rb:99 repareren (update_all of lock_version herladen) en de spec mee aanpassen; daarna import met author_id/created_on opnieuw testen met curl.
  - Issue-update met `issue[updated_on]`/`closed_on`-override testen.

## Branch redmine70-migration
- Niet aangemaakt: de enige R7-regressie vraagt ook een spec-wijziging (ontwerpkeuze), en commits in de plugin-repos werden in deze sessie door de permissie-classifier geweigerd.
- Eindresultaat harness (bijgewerkte harness van 09:26, `origin/main`, 1006-093439-s2): OK bundle, boot 0.1.0, eager load, migrations dev+test, OK rspec 147 examples 0 failures, OK smoke 64/64 (INFO 404 op `/custom_fields/1`, `/issue_statuses/1`, `/trackers/1`: de plugin-show-routes antwoorden bewust alleen onder `/extended_api`, zie curl-test).
- Rollback migraties: n.v.t. (geen migraties)


## Aanvulling coordinator
Branch `redmine70-migration` is wel gepusht, als startpunt zonder commits: gelijk aan de gebruikte branch (132fff5). Fixes die hierboven als diff staan, zijn nog niet gecommit.

