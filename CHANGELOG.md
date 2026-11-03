# Changelog

## 0.0.1

* Initial release exposing default Redmine APIs.
* Added `/extended_api` proxy that mirrors the Redmine REST API while keeping the core endpoints untouched.
* Documented every mirrored Redmine 6.1 endpoint with usage examples in the README.

## 0.0.2

* Enabled POST/PUT/PATCH/DELETE for issue statuses, trackers, enumerations, custom fields and roles.
* Added API serializers that expose all administrative options.
* Documented write operations in the README with cURL examples for JSON clients.
* Added an extended_api metadata block to each extended API template so responses explicitly state whether they originated from the extended feature set or a proxied native endpoint.

## 0.0.3

* Resolved handling of enumerations values in the enumeration custom field.

## 0.0.5

* Returned a journal payload when an issue update succeeds through the extended API, making it easier to confirm journal updates programmatically.

## 0.0.4

* Added admin-only issue override support (author_id, created_on, updated_on, and closed_on) when routed through the extended API.
* Added admin-only journal override support (user, updated_on and updated_by_id) when routed through the extended API.
* Added admin-only attachment override support (author_id and created_on) when routed through the extended API.
* Documented the new overrides in the README.

## Redmine 7 migration (branch redmine70-migration)

* Fixed: author_id/created_on/updated_on/closed_on overrides on issue create were silently lost on Rails 7.1+ (Redmine 7): update_columns added the stale lock_version to its WHERE.
* Fixed: notify=false switched mail off for the whole process (Mailer.with_deliveries), dropping mail of other requests; it now only drops the mail of its own request.
* Fixed: override values that cannot be stored (unparseable time, unknown user) are refused with 422; they were saved as NULL or failed with 500 (journals, Redmine 7 webhooks).
* Fixed: refusals (tracker, role or custom field delete, issue status in use) answer 422 with the reason in errors instead of an empty body or a 500.
* Fixed: a custom field create without a valid type answers 422 instead of 200 with HTML.
* Fixed: an issue update without changes answers 204 like core instead of a journal without id.
* Fixed: the proxy keeps the parsed form of the request (form encoded POSTs answered 500 with Rack 2).
* notify=false also silences the Redmine 7 webhooks of the request (decision of Jan, 2026-10-07).
* Issue, Journal and Attachment are patched with prepend instead of alias_method (recursed next to redmine_stealth).
* Fixed: DELETE of a tracker in use gives core's reason on Redmine 5.1 too, instead of only "Unable to delete tracker".
* Runs on Redmine 5.1, 6.1 and 7.0 (decision of Jan, 2026-10-13, replacing "Redmine 7 only" of 2026-10-07); the webhook patch is applied only where Redmine has webhooks (7.0). Tested on 5.1-stable, 6.1-stable and 7.0-stable-GEOxyz with PostgreSQL; integration tests against a real Redmine and end to end scenarios in test/e2e.
* Fixed: the .xml answers of the extended endpoints (trackers, roles, issue statuses, enumerations, custom fields, the journal of an issue update) had two top-level elements, so XML parsers refused them. The extended_api block is now inside the record's element (attributes of the array for the enumeration list). JSON unchanged.
* README: `copy_workflow_from` and a custom field's `type` belong at the top level of the request, not inside `tracker` / `custom_field`.
* Fixed (SD-18): `enumerations` were ignored on create and update of a Key/Value list (depending) custom field (201/200 with `"enumerations": []`); every format built on core's Key/Value list (`Redmine::FieldFormat::EnumerationFormat`) now takes them.
* Fixed (SD-19): in XML, `value_dependencies` and `default_value_dependencies` were written as attributes of one element, not well-formed for a parent value such as `a]`, `1` or one with a space. XML now has one element per parent value: `<value_dependencies type="array"><value_dependency parent="Belgium"><value>12</value></value_dependency></value_dependencies>`. JSON unchanged.
* Fixed (SD-20): a `.json`/`.xml` path under `/extended_api` of a controller without API authentication (`/extended_api/settings.json`, `/extended_api/admin/projects.json`) answered 500; it answers the proxy's 404 "Not a REST API endpoint".
* Fixed (SD-21): a custom field create under `/extended_api` applied attributes outside its attribute policy (core assigned the whole request first), update dropped them; both apply the policy now. Core's own paths `POST /custom_fields.json`, `PUT` and `DELETE /custom_fields/:id.json` took an administrator's API key, acted and answered 302 or 406; they answer 403 again like core without this plugin.
* Fixed: the same as SD-21 (2) for roles, trackers, issue statuses and enumerations: an administrator's API key on core's own `POST /roles.json`, `PUT`/`DELETE /roles/:id.json` (and the same for `/trackers`, `/issue_statuses`, `/enumerations`) created, changed or deleted and answered 200, 302 or 406; these paths answer 403 again like core without this plugin. Reads core accepts (index, a role's show) are unchanged; `/extended_api` keeps the writes.
* XML: Arrays were written as Ruby text (`<group_ids>[8, 9]</group_ids>`). Now proper arrays: a custom field's `group_ids` (`<group_ids type="array"><group_id>8</group_id>...`), a role's `permissions_tracker_ids` (`<permissions_tracker_ids type="array"><permission name="view_issues"><tracker_id>1</tracker_id>...</permission></permissions_tracker_ids>`), and the value of a multiple custom field of an enumeration (`<value type="array"><value>a</value>...</value>`, like core's issues). JSON unchanged.
