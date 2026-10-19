# Redmine 7 migration: redmine_extended_api

Start a Claude Code (or Codex) session on this repository, branch `redmine70-migration`, with:

> Read CLAUDE.md and docs/REDMINE7-MIGRATION.md, then carry out the Redmine 7 migration of this
> plugin as described there, on branch redmine70-migration. That includes the plugin's tests on
> PostgreSQL, every function exercised end to end on a real running Redmine in a
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
| Measured on | Redmine 7.0.1 (7.0-stable-GEOxyz + latest 7.0-stable), Rails 8.1.3.1, Ruby 3.3.6, PostgreSQL 16 (MariaDB 10.11 until 2026-10-06); since 2026-10-13 also Redmine 5.1.13 (Rails 6.1.7.10, Ruby 3.2.6) and 6.1.5 (Rails 7.2.4, Ruby 3.3.6) |
| Branch head when this file was written | `cadd602` |
| Migration session finished | 2026-10-06; Jan's decisions of 2026-10-07 built the same week; 5.1/6.1/7.0 compatibility (decision 2026-10-13) built 2026-10-13, see "Decided by Jan" and "Results" |
| Supported Redmine | 5.1, 6.1 and 7.0 (`requires_redmine 5.1`, decision 2026-10-13) |

## Already on this branch

All runs on 7.0-stable-GEOxyz (Redmine 7.0.1, Rails 8.1.3.1, Ruby 3.3.6) unless said otherwise. Every fix
has a test that fails without it. Since 2026-10-13 (decision of Jan) every run is also done on 5.1-stable and 6.1-stable.

| commit | what | found by |
|---|---|---|
| `cc640a7` | Issue overrides (author_id, created_on, updated_on, closed_on) on create were silently lost on Rails 7.1+: `update_columns` adds the stale in-memory `lock_version` to its WHERE. Now `where(id:).update_all` (the Rails 6.1 behaviour). Spec fake updated. | analysis, work list 1-2 |
| `936f804` | Test: Redmine 7 webhooks carry the imported author/dates, equal to what is stored. | work list 5 |
| `cf6f395` | DELETE of an issue status in use: 422 with core's message instead of 500 (`check_integrity` raises). | e2e |
| `de29af0` | Refused deletes (tracker/role in use, custom field) came back as an empty 422 (`render_error` answers API formats with `head`); now `{"errors":[reason]}`. | e2e |
| `04dc876` | Custom field create without a valid `type`: 422 `Type is invalid` instead of 200 with core's HTML type picker. | e2e |
| `fb4eb7e` | Override values that cannot be stored (unparseable time, unknown user id) are refused with 422 before anything is saved. Before: issue/attachment saved with created_on NULL, journal 500, and on Redmine 7 a 500 from the webhook payload after the issue was committed. | e2e |
| `9bba843` | notify=false used `Mailer.with_deliveries(false)`, which switches mail off for the whole process: mail of other requests/async jobs delivered meanwhile was lost (seen in the e2e run). Replaced by a thread-local mail interceptor. | e2e |
| `615cc1e` | Issue update without changes: 204 like core, not 200 with a journal without id. | e2e |
| `cc1a221` | Proxy dropped the parsed form but left `rack.request.form_input`: every form encoded POST/PUT through /extended_api was a 500 on Redmine 5.1 (Rack 2). JSON was fine. | tests on 5.1 |
| `d923906`, `95068f6` | Test kit: PostgreSQL provisioning as root; file mail delivery only for the server env (it leaked into the test env and made "no mail" tests pass vacuously). | setup |
| `d40fc57`, `0fc2c86`, `c6edff0` | Tests run on 5.1 too; tolerate plugins that widen core permissions (redmine_editauthor); review fix. | 5.1 run, together run, OpenAI review |
| `91f7785` | Issue, Journal and Attachment patched with `prepend` instead of `alias_method` (Jan's general decision; the old send_notification chain recursed next to redmine_stealth). | decision 2026-10-07 |
| `2d0a3b8` | notify=false / send_notification=0 also silences the Redmine 7 webhooks of the request (decision q2). | decision 2026-10-07 |
| `9c4a48d` | requires_redmine 7.0 (init.rb patches Webhook); 5.1-only test paths removed. | decision 2026-10-07 |
| `c306874` | e2e scenario `webhooks.mjs`; final e2e run, 82 screenshots. | |
| `3241c2b`, `76c3a80` | End to end scenarios (test/e2e) and screenshots (docs/e2e). | |
| `54bbe44` | Redmine 5.1, 6.1 and 7.0 again (decision 2026-10-13): requires_redmine 5.1; Webhook patch only `if defined?(::Webhook)` (without it 5.1 does not boot: `init.rb:45: uninitialized constant Webhook (NameError)`); the 5.1 test paths of `9c4a48d` restored, the webhook tests skip without Webhook; e2e: Settings tab "API" before 7.0, webhook checks only on 7.0. | decision 2026-10-13 |
| `8244f40` | DELETE of a tracker in use on 5.1 answered only "Unable to delete tracker" (5.1 has no `error_can_not_delete_tracker_html`); now core 5.1's `error_can_not_delete_tracker`. Test fails on 5.1 without it. | e2e on 5.1 |
| `204c4a8` | On 5.1 with redmine_tags (master) every POST /issues.json was a 500, SystemStackError: this plugin prepended `Issue#safe_attributes=`, redmine_tags loads after it and alias_method-chains the same method, so super looped (0 of 426 issues in session B's 5.1 gate). Issue and Attachment no longer override `safe_attributes=`; the issue overrides are set in `before_validation`, only on the issue the update names. Rspec with an alias chain fails without it (SystemStackError); integration test next to redmine_tags. | 5.1 rollout gate (session B) |
| `530d2f3` | A subtask created through /extended_api with author_id/created_on overwrote the author and created_on of its parent (the after_save override ran for every issue saved in the request; parent recalculation saves the parent). Now only the issue the request creates or updates. Integration test fails without it. | own review of `204c4a8` |
| `7ba0351`, next commit | History endpoint (decision 41 of the Jira migration, 2026-10-19): `POST /extended_api/issues/:id/history.json`, admin only; status, assignee and priority changes as journals with their own user and time through `insert_all` (no callback, no watcher, mail or webhook); the issue is not saved; optional uploads attached with their author and time; 422 for every other input, 403 for a non-admin or an archived project. 9 of 11 tests fail without it (the other 2 pin the 404s); archived-project test fails without the review fix. | decision 41, OpenAI review |
| `506603c` | `skip_journal` (decision 37 of the Jira migration, E1/E2, 2026-10-15): admin-only top-level flag on `/extended_api`; no journal for the issue update, no "Subtask added", no relation journals on create/destroy, issues saved keep `updated_on`, `PUT /extended_api/journals/:id` keeps `updated_on`/`updated_by_id`. Non-admin 403, notes with the flag 422. Callbacks and an around_action only. 9 tests fail without it (7.0 and 5.1). | decision 37 |
| `8d6caab` | No core method is overridden any more: `init_journal` and `send_notification` were still prepended (same loop risk next to a later alias_method chain on 5.1/6.1). notify=false now sets `notify = false` in `before_save` (core's `send_notification` checks `notify?`); journal overrides are set on the new journal in `before_validation`. Journal and attachment overrides only on their own record: the journal the request writes on the issue it updates, the attachment the upload creates (closing an issue gave the journals of its closed duplicates the imported user and date). Tests fail without it. Decided overnight, for Jan to confirm. | coordinator, overnight 2026-10-13 |

## Work list for the migration session

In this order: things that break, security, the GEOxyz changes, the open items, then the checks.

**Priority items**

1. Fix lib/redmine_extended_api/patches/issue_patch.rb:99 (update_columns + lock_version on Rails 8 loses author_id/created_on overrides) together with its spec. **DONE** `cc640a7` (integration test fails without it on 7.0; spec fake now records `where(id:).update_all`).

**Open items from the analysis** (Dutch; where they conflict with a decision or a priority item above, those win)

2. lib/redmine_extended_api/patches/issue_patch.rb:99 update_columns -> update_all (of lock_version herladen) zodat author_id/created_on-overrides bij issue-create weer werken; spec/issue_patch_spec.rb mee aanpassen. **DONE** with item 1 (`update_all`); curl/e2e: issue-overrides scenario.
3. Issue-update met updated_on/closed_on-override testen op R7. **DONE**: worked already on R7 (no lock_version conflict on update); covered by `test_update_issue_as_admin_persists_updated_on_and_closed_on`, a second update after an override (optimistic locking intact) and the e2e screenshot `issue-overrides-admin-update`.

**Checks**

4. Run the plugin's whole test suite on Redmine 7.0-stable-GEOxyz with PostgreSQL (MariaDB and 5.1 no longer required, decision 2026-10-07). **DONE**, numbers under "Results".
7. Jan's decisions of 2026-10-07 (prepend, webhooks with notify=false, Redmine 7 only). **DONE**, see "Decided by Jan". "Redmine 7 only" replaced on 2026-10-13, see item 8.
8. Decision of 2026-10-13: compatible with Redmine 5.1, 6.1 and 7.0 (webhook patch only when `::Webhook` is defined, requires_redmine 5.1, 5.1 test paths of `9c4a48d` back, Ruby syntax valid on the oldest supported Ruby). Tests and e2e on 5.1-stable, 6.1-stable and 7.0-stable-GEOxyz with PostgreSQL. **DONE** `54bbe44`, `8244f40`; numbers under "Results".
5. Check Redmine 7 webhooks against this plugin (see "Rules"), and note the result here even if nothing is needed. **DONE**: the issue payload is rendered in `after_*_commit`, after the plugin's `after_save` wrote the overrides, so `issue.created`/`issue.updated` carry the imported author and dates, equal to the database (integration test + real webhook received in the e2e run, screenshot `issue-overrides-webhook-payloads`). An unparseable override date used to make the webhook payload raise (500 after commit): fixed by `fb4eb7e`. notify=false does not suppress webhooks (mail only): see open question 2.
6. Verify every feature of the plugin by hand on a running Redmine 7 (screenshots). **DONE**, see "Inventory of functions".

## GEOxyz changes to review or re-apply

Own plugin: all of it is GEOxyz code, so there is nothing to re-apply. While migrating, hold the code you touch to the rules below; list larger quality problems you find in the work list instead of fixing them in passing.

## After the upgrade (production)

Actions the person doing the upgrade must take, or know about, for this plugin:

- No migrations, no settings, no files. Deploy the branch and restart. `main` had this branch from
  merge `4d75044` until it was set back to `132fff5` the same day (see q5). The plugin runs on Redmine 5.1, 6.1 and 7.0
  (decision 2026-10-13); on 5.1 and 6.1 there are no webhooks, so the webhook part of notify=false does nothing there.
- notify=false / send_notification=0 on /extended_api now also suppresses the Redmine 7 webhooks of that
  request (decision q2): systems fed by webhooks do not see imports made that way.
- Behaviour changes API clients may notice (all on `/extended_api`, all fixes): an admin override with a
  value that cannot be stored now answers 422 (`"Created is invalid"`, `"Author is invalid"`) instead of
  saving NULL/dangling data; refused deletes now carry the reason in `errors`; a custom field create
  without `type` answers 422 instead of HTML; an issue update without changes answers 204 like core.
- If an import ran with garbage dates before, look for broken rows:
  `Issue.where(created_on: nil)`, `Attachment.where(created_on: nil)`, issues/journals whose
  author_id/user_id has no user.
- `skip_journal` (2026-10-15) is opt-in per request: nothing to configure; clients that do not send it see no change.
- REST API stays required (Administration > Settings > **Integrations** on Redmine 7, the tab was "API").

## Results

History endpoint (decision 41, 2026-10-19, PostgreSQL 16.15, branch after `7ba0351` plus three review rounds):

| run | result |
|---|---|
| tests, 5.1-stable (Ruby 3.2.6) | minitest 66 runs, 293 assertions, 0 failures, 0 errors, 8 skips; rspec 170 examples, 0 failures |
| tests, 6.1-stable | minitest 66 runs, 349 assertions, 0 failures, 0 errors, 8 skips; rspec 170 examples, 0 failures |
| tests, 7.0-stable-GEOxyz | minitest 66 runs, 376 assertions, 0 failures, 0 errors, 1 skip; rspec 170 examples, 0 failures |
| the new test file without the code (7.0) | 11 runs, 9 failures (the 2 that pass pin the 404s, which also hold without the endpoint); archived-project test without the review fix: 1 failure |
| e2e 7.0, production mode, with redmine_agile (redmine70-migration `0b57a01`) | smoke + core + 14 scenarios, 95 screenshots, 0 problems; the 6 `issue-history-*` screenshots looked at and committed: history in time order around the imported comment, "Updated over 2 years ago" unchanged, Watchers (0), jira-history.json by Reporter E2E 03/20/2024; cumulative flow Closed every day before, New / In Progress from 03-02 / Resolved from 03-10 / Closed from 03-15 after |
| e2e 7.0 without redmine_agile | 93 screenshots, 0 problems (chart steps skipped) |
| e2e 5.1/6.1 | not run for this change; the request tests run on both |
| Ruby 2.7 syntax | 46 files, 0 errors |
| OpenAI review `de4ab98..7ba0351` | `docs/reviews/openai-2026-10-19-7ba0351.md`: 2 findings, both fixed (e2e without redmine_agile; archived project); second run `openai-2026-10-19-a58e2e7.md`: 3 findings: MySQL id read-back fixed (LAST_INSERT_ID on the same connection, not run here), reuse of an attached file's token refuted with a new test (core's find_by_token already refuses it), token clearing not applicable (no token column); third run `openai-2026-10-19-e87ed79.md`: 1 finding, fixed (the same upload twice gave a 500 after a partial write, now 422 with rollback, test fails without it) |
| not tested | the MySQL path without RETURNING (PostgreSQL only, decision 2026-10-07) |

After `506603c` (skip_journal, 2026-10-15, PostgreSQL 16.15):

| run | result |
|---|---|
| with the 44 GEOxyz plugins, 7.0-stable-GEOxyz 71b9479 (coordinator) | on `8e7096c` 1 failure (non-admin test, redmine_view_issue_description refuses jsmith); test guard `ecc7dde`; then minitest 51 runs, 215 assertions, 0 failures, 1 skip; rspec 170 examples, 0 failures |
| tests, 5.1-stable (5.1.13, Ruby 3.2.6) | minitest 51 runs, 162 assertions, 0 failures, 0 errors, 8 skips; rspec 170 examples, 0 failures |
| tests, 6.1-stable | minitest 51 runs, 191 assertions, 0 failures, 0 errors, 8 skips; rspec 170 examples, 0 failures |
| tests, 7.0-stable-GEOxyz | minitest 51 runs, 216 assertions, 0 failures, 0 errors, 1 skip; rspec 170 examples, 0 failures |
| baseline before the change (7.0) | minitest 34 runs, 134 assertions, 0 failures, 1 skip; rspec 167 examples, 0 failures |
| new test file without the lib change | 7.0: 17 runs, 9 failures; 5.1: 17 runs, 9 failures (every flag case; the 8 cases without the flag, which pin today's journals, pass) |
| e2e 7.0-stable-GEOxyz, production mode | smoke + core + 13 scenarios, 89 screenshots, 0 problems; the 7 new `skip-journal-*` screenshots looked at and committed, the others unchanged and not re-committed |
| e2e 5.1/6.1 | not run for this change (the code paths are the same callbacks; the integration tests run on both) |
| Ruby 2.7 syntax | 44 files, 0 errors (`Parser::Ruby27`) |
| OpenAI review `d103a2d..506603c` | `docs/reviews/openai-2026-10-15-506603c.md`: no findings |
| own review | one fix before the commit: the notes check used `respond_to?(:[])`, a string `issue` param would have raised; now `respond_to?(:key?)`. Seen in the browser: without the flag the update also makes the admin a watcher (core `Journal#add_watcher`); with the flag not, since the journal is not stored. |

After `8d6caab` (overnight 2026-10-13, PostgreSQL 16.15):

| run | result |
|---|---|
| tests, 5.1-stable | minitest 34 runs, 96 assertions, 0 failures, 0 errors, 8 skips; rspec 167 examples, 0 failures |
| tests, 6.1-stable | minitest 34 runs, 109 assertions, 0 failures, 0 errors, 8 skips; rspec 167 examples, 0 failures |
| tests, 7.0-stable-GEOxyz | minitest 34 runs, 134 assertions, 0 failures, 0 errors, 1 skip; rspec 167 examples, 0 failures |
| the same tests on the lib of `0e8123b` (7.0) | rspec 17 failures (among them SystemStackError with an alias_method chain on init_journal and on send_notification, journal on another issue, existing attachment); duplicates integration test: expected user 1 |
| with redmine_tags master on 5.1 | not run again: this session's permission check refused running external plugin code; session B2's 5.1 gate with the production plugin set covers it |
| e2e, production mode | 5.1: 78 screenshots, 6.1: 78, 7.0: 82; 0 problems each (notifications and webhooks scenarios included; not re-committed, no page changed) |
| Ruby 2.7 syntax | 50 files, 0 errors |
| OpenAI review of `8d6caab` | `docs/reviews/openai-2026-10-13-8d6caab.md`: no findings |
| 5.1 rollout gate (session B2, production plugin set, branch at `c38e381`) | GREEN: full fresh run GEOS+SIS+OAC, verify 22 checks 0 failures, script results equal to `main` `132fff5`, no SystemStackError in the puma log (reported by the coordinator, 2026-10-13) |

After `204c4a8` and `530d2f3` (2026-10-13, PostgreSQL 16.15):

| run | result |
|---|---|
| 5.1.13 with redmine_tags master, before the fix | `Issue.new.safe_attributes = {...}`: `SystemStackError: stack level too deep`; the integration test hung until the 600 s timeout |
| 5.1.13 with redmine_tags master, after | `Issue.new.safe_attributes = {...}` no error; `extended_api_other_plugins_test` 1 run, 9 assertions, 0 failures |
| tests, 5.1-stable (without redmine_tags: running the whole suite with it again was refused by this session's permission check) | minitest 33 runs, 91 assertions, 0 failures, 0 errors, 8 skips (webhooks, redmine_tags test); rspec 164 examples, 0 failures |
| tests, 6.1-stable | minitest 33 runs, 104 assertions, 0 failures, 0 errors, 8 skips; rspec 164 examples, 0 failures |
| tests, 7.0-stable-GEOxyz | minitest 33 runs, 129 assertions, 0 failures, 0 errors, 1 skip (redmine_tags test); rspec 164 examples, 0 failures |
| subtask before `530d2f3` (7.0) | parent author 2 -> 3, created_on 2026-10-10 -> 2020-01-02; after: parent unchanged |
| e2e, production mode | 5.1: 78 screenshots, 6.1: 78, 7.0: 82; 0 problems each (not re-committed: no page changed, the run went to a scratch folder) |
| Ruby 2.7 syntax | 50 files, 0 errors |
| OpenAI review `574d4bb..530d2f3` | `docs/reviews/openai-2026-10-13-530d2f3.md`: no findings |
| not done | the 5.1 rollout gate itself (session B reruns it); `main` still at `574d4bb`, without these two fixes |

After the decision of 2026-10-13 (5.1, 6.1 and 7.0), PostgreSQL 16.15, branch at `8244f40` plus the e2e caption fix:

| run | result |
|---|---|
| tests, 5.1-stable (5.1.13, Rails 6.1.7.10, Ruby 3.2.6) | minitest 31 runs, 87 assertions, 0 failures, 0 errors, 7 skips (the webhook tests: no webhooks before 7.0); rspec 161 examples, 0 failures |
| tests, 6.1-stable (6.1.5, Rails 7.2.4, Ruby 3.3.6) | minitest 31 runs, 100 assertions, 0 failures, 0 errors, 7 skips (same); rspec 161 examples, 0 failures |
| tests, 7.0-stable-GEOxyz (7.0.1, Rails 8.1.3.1, Ruby 3.3.6) | minitest 31 runs, 125 assertions, 0 failures, 0 errors, 0 skips; rspec 161 examples, 0 failures |
| boot on 5.1 without the `defined?(::Webhook)` guard | `init.rb:45:in '<top (required)>': uninitialized constant Webhook (NameError)`; with it: boots |
| Ruby syntax, oldest supported Ruby | all 49 Ruby files of the plugin (lib, app, init, config, spec, test, .codex) parse with `Parser::Ruby27` (parser gem 3.3.12, Ruby 2.7 grammar: the oldest Ruby of Redmine 5.1); the check rejects Ruby 3.0 endless methods. Not run on a real Ruby 2.7/3.0/3.1 (not installed here). |
| e2e 5.1-stable, production mode | smoke + core + 12 scenarios, 78 screenshots, 0 problems (`docs/e2e/redmine-5.1/`); webhooks: two screenshots, Settings > API has no webhook setting and `/webhooks` is 404 |
| e2e 6.1-stable, production mode | smoke + core + 12 scenarios, 78 screenshots, 0 problems (`docs/e2e/redmine-6.1/`) |
| e2e 7.0-stable-GEOxyz, production mode | smoke + core + 12 scenarios, 82 screenshots, 0 problems (`docs/e2e/`) |
| screenshots looked at | all 238 opened (by me and three review agents, one per version) against their captions: no 500, no error page, no wrong user, every HTTP code as captioned. One caption of this change promised more than it showed (webhooks-none-before-7: the 404 was not in the picture): split into two screenshots. The rest are older, minor and identical on all three versions; listed under "Observations not fixed". |
| OpenAI review | `docs/reviews/openai-2026-10-13-77b07ac.md` (diff 712f281..77b07ac): no findings |
| own review | the guard only decides whether the Webhook patch is prepended; on 7.0 behaviour is unchanged (webhook tests green, webhooks e2e 0 problems). The tracker fallback only changes the message where the _html key is missing (5.1). No findings. |
| not run | MariaDB (decision 2026-10-07: PostgreSQL only); together with the other GEOxyz plugins on 5.1/6.1 (their 5.1/6.1 state is not part of this task) |

After Jan's decisions (2026-10-07, PostgreSQL 16.15):

| run | result |
|---|---|
| tests, 7.0-stable-GEOxyz, alone | minitest 31 runs, 123 assertions, 0 failures; rspec 161 examples, 0 failures |
| tests, with 35 other GEOxyz plugins (all public jcatrysse plugins, redmine70-migration branches) | minitest 31 runs, 122 assertions, 0 failures; rspec 161 examples, 0 failures |
| e2e, alone, production mode | smoke + core + 12 scenarios, 82 screenshots, 0 problems (`docs/e2e/`) |
| e2e, with the 35 plugins | issue list and issue page 200. Project > Settings 500: `super: no superclass method project_settings_tabs`, in the ProjectsHelper chain of redmine_mail_digest (`project_settings_tabs_with_issue_digest`, alias_method), redmine_itil_priority, redmine_ai_summary and others; this plugin does not patch ProjectsHelper. Our scenarios: differences only from other plugins (redmine_editauthor sets author_id, redmine_view_issue_description refuses reporter); the webhook checks of the old issue-overrides scenario failed there because it imported with notify=false, which now silences webhooks by decision, fixed in the scenario. |
| OpenAI review of the new commits | `docs/reviews/openai-2026-10-07-c306874.md`: no findings |
| own review of the new commits | prepend keeps behaviour and visibility (send_notification private like core); the webhook skip only acts while the request's thread-local flag is set, which ends in the controller's ensure; core path unchanged. No findings. |

Before (2026-10-06):


| run | result |
|---|---|
| tests, 7.0-stable-GEOxyz, PostgreSQL 16.15 | minitest 25 runs, 108 assertions, 0 failures; rspec 157 examples, 0 failures |
| tests, 7.0-stable-GEOxyz, MariaDB 10.11.14 | minitest 25 runs, 108 assertions, 0 failures; rspec 157 examples, 0 failures |
| tests, 5.1-stable, PostgreSQL, Ruby 3.2.6 | minitest 25 runs, 0 failures, 1 skip (webhook test: no webhooks before 7.0); rspec 157 examples, 0 failures |
| baseline before changes (7.0, PostgreSQL) | rspec 147 examples, 0 failures (all doubles: the update_columns bug was invisible to them) |
| e2e, PostgreSQL, production mode | smoke + core + 11 scenarios, 78 screenshots, 0 problems (`docs/e2e/`) |
| e2e, MariaDB, production mode | same set, 78 screenshots, 0 problems (not committed, identical captions) |
| together with redmine_depending_custom_fields, redmine_view_issue_description, redmine_itil_priority, redmine_editauthor (their redmine70-migration branches), PostgreSQL | tests green after `0fc2c86`; e2e: no failure caused by this plugin. Differences are the other plugins' features and equal on core and extended paths: with redmine_editauthor a non-admin with its permission (and the core path) sets `author_id` (created_on stays ignored); with redmine_view_issue_description the reporter/outsider get 403 on `/issues/1` (kit core flow) and on notes. |
| migrations up/down | n.v.t.: the plugin has no migrations. Boot and eager load: production server started on both databases. |
| OpenAI review | `docs/reviews/openai-2026-10-06-0fc2c86.md`: 6 findings, 1 fixed (`c6edff0`), 5 refuted with a resolution each; second run `openai-2026-10-06-cc2da3b.md`: no findings |

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
| notify=false / send_notification=0 silence the Redmine 7 webhooks of the request (decision q2) | any API user; core path untouched; 7.0 only | `webhooks.mjs` | webhooks-webhook, -calls, -received, -quiet-issue; on 5.1/6.1 webhooks-none-before-7, -none-before-7-404 |
| History endpoint: imported status, assignee and priority changes as journals, uploads attached, issue untouched; redmine_agile's cumulative flow before and after (when installed) | admin API; 403 for others and archived projects, 401 anonymous, 404 on the core path, 422 invalid input | `issue_history.mjs` | issue-history-before-page, -before-cumulative-flow, -admin, -after-page, -after-cumulative-flow, -refused |
| `skip_journal`: import post-processing without journal or edit trace (issue update, parent, relations, comment rewrite) | admin API; 403 for others, 422 with notes; ignored on the core path | `skip_journal.mjs` | skip-journal-admin, -child-page, -parent-page, -without-flag, -without-flag-page, -refused, -member-page |
| Show routes only under `/extended_api` (core `/trackers/1.json` etc. 404) | API | in the scenarios above and `smoke.mjs` | smoke-13..15, the -refused screenshots |

Users per scenario: admin (everything), manager (all project permissions, not admin: admin endpoints
403, overrides ignored), reporter (core Reporter role: 403 where core refuses), outsider (no membership:
private project refused), anonymous (401). No "before" pictures on 5.1: the plugin has no layout, the
behaviour differences are shown by the tests that fail without each fix.

Since 2026-10-13 the same scenarios run on 5.1-stable and 6.1-stable too; their screenshots are in
`docs/e2e/redmine-5.1/` and `docs/e2e/redmine-6.1/` (same names; the webhook screenshots of
issue-overrides and webhooks exist only on 7.0, `webhooks-none-before-7` only on 5.1/6.1).

## Observations not fixed (minor, pre-existing)

- (Fixed in `8d6caab`: journal and attachment overrides on other records; `init_journal` and
  `send_notification` prepended.)

Found in the screenshot review of 2026-10-13, the same on 5.1, 6.1 and 7.0 (scenarios and plugin
unchanged by this work, so recorded, not fixed):

- `x-redmine-extended-api` says `native` on issue create and upload calls where the admin overrides
  were applied, and on `PUT /extended_api/roles/999999.json` (404); other unknown-id 404s say `extended`.
- Enumerations: the index returns `"type": "time_entry_activities"`, create/update return
  `"type": "TimeEntryActivity"`.
- An issue update with `updated_on`/`closed_on` in the past creates its journal dated now (the issue page
  shows "Updated over 5 years ago" next to a journal of a minute ago). Sending `journal[created_on]` avoids it.
- Captions that claim a little more than the picture shows: custom-fields-admin-edit (the options sit behind
  "Possible values > Edit"), custom-fields-delete (only field 1 is read back), proxy-same-as-core (no core
  XML row), roles-admin-crud (the copied workflow is not visible), notifications-calls (no relation call
  without notify=false), webhooks-webhook (7.0: a second webhook left by issue-overrides). The checks behind
  them pass; the pictures are incomplete.
- Issue statuses list: core's "...in the workflows(Edit)" has no space (core, not the plugin).

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

## Decided by Jan

Recorded 2026-10-07 from `docs/DECISIONS-2026-10-07.md` (Jan's answers in the coordinating session);
notes verbatim. Final.

Answers of 2026-10-15 (multiple choice in the coordinating session): Jan agrees with all four choices made
while building `skip_journal` (`506603c`); final.
- **redmine_extended_api-q9**, name and form: `skip_journal`, top-level next to `notify`, in the query
  string or the JSON body; `true`/`1`/`yes`/`on` switch it on, anything else is the normal request.
- **redmine_extended_api-q10**, a non-admin sending `skip_journal=true`: refused, `403` with core's
  "You are not authorized to access this page.", nothing changed. Alternative not taken: ignore the
  flag silently (the import would not notice it wrote journals).
- **redmine_extended_api-q11**, `skip_journal` with `notes`/`private_notes` on an issue update: refused,
  `422` "Notes is invalid", because the notes live in the journal and would be lost. Comments are
  imported without the flag (with the journal overrides) and rewritten with it through
  `PUT /extended_api/journals/:id.json`.
- **redmine_extended_api-q12**, `updated_on`: under the flag every issue the request saves keeps its
  `updated_on` (the updated issue, a parent recalculated or given "Subtask added", a rescheduled
  follower), except the issue whose own `updated_on` override the request sends.

Answers of 2026-10-13 to the points taken while waiting (through the coordinator):
- **redmine_extended_api-q4**, oldest Ruby: production 5.1 runs Ruby 3.1 or newer. The run on 3.2.6
  plus the Ruby 2.7 parser check is enough; no extra Ruby runs.
- **redmine_extended_api-q5**, where the 5.1 version runs: merge `redmine70-migration` into `main`,
  but not now. **Merged on 2026-10-13 on Jan's direct instruction, before session B's 5.1 rerun**
  (`4d75044`, normal merge, main `132fff5` was an ancestor, no conflicts). Tests on the merged
  `main`, PostgreSQL 16.15: 5.1-stable minitest 31 runs, 0 failures, 7 skips, rspec 161/0;
  6.1-stable 31 runs, 0 failures, 7 skips, rspec 161/0; 7.0-stable-GEOxyz 31 runs, 125 assertions,
  0 failures, 0 skips, rspec 161/0. e2e not repeated: the merged tree is identical to
  `redmine70-migration` at `d987292`, whose e2e runs are under "Results". **Set back the same day**
  on Jan's instruction, after session B's 5.1 gate was red (SystemStackError next to redmine_tags,
  fixed in `204c4a8`): `main` = `132fff5` again, what production runs, with
  `git push --force-with-lease=main:574d4bb origin 132fff5:refs/heads/main`. The next merge into
  `main` comes after B's 5.1 gate is green on this branch and Jan's own go; the identity rewrite of
  this branch (author/committer Jan, trailers removed, review files renamed) is done once, right
  before that merge. Original conditions: session B's 5.1 baseline rerun with
  redmine_extended_api `redmine70-migration` is green, and Jan gives an explicit go through the
  coordinator. The 2026-10-07 rule "nothing to main" is lifted for that one merge only. When the go
  comes: a normal merge, no force-push, tests re-run on the merged `main`.
- **redmine_extended_api-q6**: yes, on 5.1 and 6.1 notify=false only silences mail, and that is enough.

For this plugin (2026-10-13), replacing "Redmine 7 only" of 2026-10-07 below:
- Compatible with Redmine 5.1, 6.1 and 7.0: the webhook patch only when `::Webhook` is defined,
  requires_redmine 5.1, the 5.1 test paths removed in `9c4a48d` restored, Ruby syntax valid on the
  oldest supported Ruby; tests and e2e on 5.1-stable, 6.1-stable and 7.0-stable-GEOxyz with
  PostgreSQL. (Context: jcatrysse/jira2redmine_migration, docs/MIGRATION-PLAN.md, work list 4.)
  Done: `54bbe44`, `8244f40`.

General, for every GEOxyz plugin (2026-10-07):
- GEOxyz goes straight to Redmine 7: no backports to 5.1, nothing is cherry-picked to `main`;
  `redmine70-migration` goes live with Redmine 7. 5.1 compatibility is no longer required and no code
  path exists only for 5.1. Done here: `9c4a48d` (requires_redmine 7.0, 5.1-only test paths removed).
  **For this plugin replaced on 2026-10-13** (see above): 5.1, 6.1 and 7.0 again.
- Production runs PostgreSQL 16 only; tests and e2e run on PostgreSQL. MariaDB runs are no longer
  required (the earlier MariaDB results below are kept as history).
- deface without a version constraint: n.v.t., this plugin does not use deface.
- Core methods other plugins also patch are patched with `prepend`, never `alias_method`. Done:
  `91f7785` (Issue#safe_attributes=, Issue#init_journal, Attachment#safe_attributes=,
  Issue/Journal#send_notification; redmine_stealth prepends send_notification, which made the old
  chain recurse). With 35 other GEOxyz plugins installed: issue list and issue page 200; Project >
  Settings 500, but not from this plugin (see "Together").
- GitHub Actions stay manual only (`workflow_dispatch`): unchanged.

For this plugin:
1. **redmine_extended_api-q1**, invalid date or unknown user in an import. Jan chose A: "Weigeren met een
   foutmelding (422)" (Een import die foute gegevens stuurt, merkt dat meteen, en er komen geen kapotte
   rijen meer in de database.). Already built in `fb4eb7e`; kept.
2. **redmine_extended_api-q2**, should notify=false also silence webhooks? Jan chose B: "Ook webhooks
   stilleggen" (Imports blijven onzichtbaar voor gekoppelde systemen, die daardoor kunnen afwijken van
   Redmine.). Built in `2d0a3b8` (Webhook.trigger prepended, skipped while the request's suppression
   flag is set), test `extended_api_webhooks_test.rb`, e2e `webhooks.mjs`.
3. **redmine_extended_api-q3**, issue update without changes. Jan chose A: "204, zoals Redmine zelf (zo
   laten)" (Gelijk aan de gewone Redmine-API; het oude antwoord bevatte niets bruikbaars.). Already built
   in `615cc1e`; kept.

## skip_journal (decision 37 of the Jira migration, 2026-10-15)

Asked by Jan through the coordinator (jcatrysse/jira2redmine_migration, docs/MIGRATION-PLAN.md, E1 and
E2): the Jira import must leave no visible trace of its technical post-processing. Built in `506603c`.

Who: admin API users, on `/extended_api` only. Form: top-level `skip_journal=true` (query string or
JSON body), next to `notify`. Effect while the request runs (thread-local, restored in an ensure):

- `Journal` gets a `before_save` (prepended in the chain) that stops every new journal: the issue
  update's journal (`Issue#create_journal`), "Subtask added" (`create_parent_issue_journal`), the
  relation journals (`IssueRelation#init_journals` + `relation_added/removed`). Core ignores the false
  from `Journal#save` in all three. No core method is overridden (q7).
- `Issue` gets an `after_save` that writes back `updated_on` of every issue the request saves, unless
  the request's own `updated_on` override applies to it.
- `JournalsController` gets an `around_action` on `update` (after `find_journal` and `authorize`);
  `Journal`'s `after_save` puts `updated_on` and `updated_by_id` back after the edit.
- Non-admin: 403. With notes on an issue update: 422. `notify=false` is independent and still needed
  for no mail and no webhooks.

Example (the migration's second pass):

```sh
curl -X PUT -H 'Content-Type: application/json' -H 'X-Redmine-API-Key: <admin key>' \
  -d '{"issue":{"description":"See #124","parent_issue_id":120},"notify":false,"skip_journal":true}' \
  https://redmine.example.com/extended_api/issues/123.json        # 204, no journal
curl -X PUT -H 'Content-Type: application/json' -H 'X-Redmine-API-Key: <admin key>' \
  -d '{"journal":{"notes":"Imported comment, see #124"},"skip_journal":true}' \
  https://redmine.example.com/extended_api/journals/456.json      # 204, not "Edited"
```

## History endpoint (decision 41 of the Jira migration, 2026-10-19)

Asked by Jan through the coordinator (jcatrysse/jira2redmine_migration `docs/research/JIRA-HISTORY.md`
sections 2.1, 2.4, 2.5; decision 41 in `docs/MIGRATION-PLAN.md`): the main Jira history (status,
assignee, priority changes) as real Redmine journals with Jira's user and time, without the issue
looking "updated just now". `POST /extended_api/issues/:id/history.json`, contract and example in the
README ("Imported issue history"). Controller `app/controllers/extended_api_issue_histories_controller.rb`,
route in `config/routes.rb` (only answers through `/extended_api`, like the show routes).

- Journals and details go in with `insert_all` in one transaction: no Journal callback (no
  `add_watcher`, no mail, no other plugin's job), no Issue save (no webhook, updated_on, closed_on,
  status_id, lock_version and watchers unchanged).
- Validation before anything is written; 422 lists every reason.
- Uploads: `update_columns` on the attachment (container, author, created_on, filename through core's
  sanitizing setter, content type, description); no journal.
- redmine_agile's cumulative flow reads `journal_details` with `journals.created_on`, so it follows the
  imported history (e2e screenshots).

## Branch history rewrite (2026-10-14)

On Jan's instruction, once before the merge into `main`: every commit after `bf7e6c4` got author and
committer Jan Catrysse and lost its Co-Authored-By/Claude-Session trailers (`git filter-branch`, dates
and merge parents kept). Proof: `git diff` old/new tip empty, every commit has the same tree and dates
as before, 0 mentions of Claude/anthropic/session links in bf7e6c4..HEAD. Old tip `33d7bf2`, new tip
`c31cc47`; hashes quoted in this file and the review file names were updated to the new ones.

Merged into `main` on 2026-10-14 on Jan's go, after the rewrite and after session B2's green 5.1 gate:
`main` fast-forwarded from `132fff5` to `c24538f` (no force; the branch already holds the merge
`4d75044` with `132fff5` as first parent, so no new commit was needed). Tests on that tree, PostgreSQL
16.15: 5.1-stable minitest 34 runs, 0 failures, 8 skips, rspec 167/0; 6.1-stable 34 runs, 0 failures,
8 skips, rspec 167/0; 7.0-stable-GEOxyz 34 runs, 134 assertions, 0 failures, 1 skip, rspec 167/0.

Second pass the same day, on Jan's instruction, done by Jan in his own clone: the Co-Authored-By/
Claude-Session trailers were also removed from the older commits (all 46 commits after `132fff5`,
`git filter-branch --msg-filter` only; author, committer, dates and trees unchanged, merge parent
`132fff5` kept). Old tip `c0b32b0`, new tip `4713222`, diff empty, 0 trailers left. Every hash quoted
in this file and in the review file names refers to the commits after this second pass.

## Open questions for Jan

Decided overnight (2026-10-13), for Jan to confirm:
- **redmine_extended_api-q7**, how the plugin coexists with other plugins on 5.1/6.1: it overrides
  no core method at all (no prepend, no alias_method on safe_attributes=, init_journal,
  send_notification); everything goes through model callbacks (`before_validation`, `before_save`,
  `after_save`), which do not interfere with other plugins' method chains. Alternative not taken:
  keep prepend and defer it until after all plugins load (fragile, depends on load order).
- **redmine_extended_api-q8**, scope of the import overrides: only the record the request creates or
  updates (the issue, its new journal, the uploaded attachment), never other records saved along with
  it (parent, duplicates, related issues). notify=false keeps silencing every mail of the request.

Decided while building the history endpoint (2026-10-19), for Jan to confirm:
- **redmine_extended_api-q13**, closed projects: the history endpoint writes into an issue of a closed
  project (an import may close its projects before the history pass); archived projects are refused
  (403), as core does for every write.
- **redmine_extended_api-q14**, "last updated by": Redmine takes the user of the journal with the
  highest id (`Issue#last_updated_by`, and the issue list column). History written after newer
  comments therefore makes the last history user the "last updated by", not the user of the latest
  event by time. The endpoint cannot change ids; keeping it right needs the history written before
  the comments of the issue, or not caring. updated_on is not affected.

- Nothing else: q9 to q12 were answered on 2026-10-15, q4 to q6 on 2026-10-13, see "Decided by Jan".


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
   - the plugin's tests on Redmine 7.0-stable-GEOxyz with PostgreSQL;
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
6. **Portability**: PostgreSQL is what GEOxyz runs (decision 2026-10-07); keep SQL portable where it
   costs nothing. Migrations must be reversible and are run down and up on PostgreSQL.
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
- **Redmine 5.1, 6.1 and 7.0** (decision of Jan, 2026-10-13, replacing "Redmine 7 only" of
  2026-10-07): code that only exists on 7.0 (Webhook) is used behind `defined?`; tests skip what
  an older Redmine lacks, never weaker; Ruby syntax valid on Ruby 2.7; tests and e2e on
  5.1-stable, 6.1-stable and 7.0-stable-GEOxyz.
- **PostgreSQL** (decision of Jan, 2026-10-07): tests and e2e on PostgreSQL 16; keep SQL portable where it
  costs nothing; a MariaDB-only problem is a note, not a blocker.
- **prepend, not alias_method** (decision of Jan, 2026-10-07) for core methods other plugins also patch.
- **Git**: work on `redmine70-migration` only; never push to the default branch; never force-push
  a branch someone else uses. Descriptive commit messages (what and why). Push after every
  commit, together with the updated status in this file: a cloud session can stop at a usage
  limit, and work that is not pushed is lost with its container.
- **GitHub Actions**: manual only (`workflow_dispatch`). Do not add push, pull_request or schedule
  triggers.

## Definition of done

- All items of the work list are done or explicitly deferred with a reason, in this file.
- The plugin's tests are green on Redmine 5.1-stable, 6.1-stable and 7.0-stable-GEOxyz with
  PostgreSQL (numbers in this file); boot, production-like eager load, migrations up/down OK.
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

