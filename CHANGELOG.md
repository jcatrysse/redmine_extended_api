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
* Requires Redmine 7 (GEOxyz goes straight to 7.0; decision of Jan, 2026-10-07). Tested on 7.0-stable-GEOxyz with PostgreSQL; integration tests against a real Redmine and end to end scenarios in test/e2e.
