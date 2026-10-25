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

## SPR-383 — Sprintly role model on the server

* Every Sprintly SPA permission is a Redmine permission (`sprintly__<id>`); a role also carries the core permissions it implies, so Redmine enforces it.
* Role assignments (global per user and group, default role, per-project overrides) are stored in the plugin settings and written into project memberships; the `admin` flag follows the `admin.access` permission.
* New `/sprintly/...` endpoints (also under `/extended_api`): `me`, `roles`, `assignments`, `projects/:id/assignments`, `import`, `principals`, `custom_fields`, `app_config`.
* Finer checks than core: status changes without configured workflows, assignee/priority/sprint fields, watching others, sprint create/edit/delete, wiki create vs edit, time entry edit/delete, project creation as a global permission.
* Inert until a tenant is imported (`POST /sprintly/import`).
* Gists (project and sprint files): adding needs `gists.create`, renaming `gists.edit`, deleting `gists.delete`; core grants all three with `manage_files`.
