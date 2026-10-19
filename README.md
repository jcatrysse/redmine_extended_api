# Redmine Extended API

**ATTENTION: ALPHA STAGE**

This plugin exposes Redmine's REST API under an alternate base path and unlocks write access for administrative resources that are read-only in vanilla Redmine. Every request keeps the native controllers, permission checks, and response formats, so it behaves exactly like Redmine would if those endpoints were public.

## Overview

- `/extended_api` is a drop-in proxy of the core REST API. Anything that works under the default paths continues to work unchanged when you prepend the new base path.
- Additional write operations are enabled for catalogue-like resources (roles, custom fields, issue statuses, trackers, and enumerations). The plugin reuses the built-in controllers, so validation rules and workflows stay identical to the web UI.
- Optional integrations (for example `redmine_depending_custom_fields`) automatically surface their own REST attributes whenever they expose compatible controllers.

## Core vs. extended coverage

| Resource category                                                                                    | Core Redmine behaviour                               | What the plugin adds                                                                                      | Notes                                                                              |
|------------------------------------------------------------------------------------------------------|------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------|
| Issues, projects, time tracking, files, wiki, news, memberships, queries, search, repositories, etc. | Already exposed through the official REST API.       | Proxied verbatim under `/extended_api`.                                                                   | Use this when you want an isolated gateway without touching existing integrations. |
| Administrative catalogs: roles, trackers, issue statuses, enumerations, custom fields                | Limited to HTML UI in core. No REST write endpoints. | Adds authenticated POST/PUT/PATCH/DELETE plus enriched payloads while keeping Redmine's permission model. | These endpoints live exclusively under `/extended_api`.                            |
| Third-party plugins with API-aware controllers (e.g. `redmine_depending_custom_fields`)              | Varies per plugin.                                   | Their API actions are automatically available when routed through `/extended_api`.                        | The extended API exposes any additional attributes permitted by the plugin.        |

If you only need core behaviour, keep using the official REST endpoints. The plugin does not override or patch the original routes.
All new endpoints will have a recognisable JSON /XML payload:
``` json
{"extended_api":{"mode":"extended","fallback_to_native":false}}
```

## Installation

Requires Redmine 5.1, 6.1 or 7.0 (tested on 5.1-stable, 6.1-stable and 7.0-stable-GEOxyz with PostgreSQL).

1. Clone this repository into your Redmine plugins directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/jcatrysse/redmine_extended_api.git
   ```
2. Restart Redmine.

No database migrations are required at this stage.

## Testing

`RAILS_ENV=test bundle exec rspec plugins/redmine_extended_api/spec`

## Usage

All REST API calls that ship with Redmine remain available at their original paths. The plugin adds a drop-in replacement under `/extended_api` where the behaviour, payloads, and permissions are identical because every request is proxied back to the core Rails stack.

> **Note**
> Only controllers/actions that support API authentication in Redmine are exposed through the proxy. Requests targeting HTML-only controllers (e.g. `/my/page`) return `404` from `/extended_api` because those routes are intentionally outside the scope.

### Authentication & formats

- **Authentication**: identical to core Redmine. Use an API key via the `X-Redmine-API-Key` header or HTTP Basic with a user account that has REST access.
- **Formats**: JSON (`.json`) and XML (`.xml`) endpoints only. Requests without one of these extensions return `404` to avoid exposing the HTML UI through `/extended_api`.

### Base paths

| Description       | Core path           | Extended path                    |
|-------------------|---------------------|----------------------------------|
| API root          | `/`                 | `/extended_api`                  |
| Issues collection | `/issues`           | `/extended_api/issues`           |
| Nested endpoints  | `/projects/:id/...` | `/extended_api/projects/:id/...` |

The rule is: prepend `/extended_api` to any Redmine REST API path (including nested ones) and keep the rest unchanged.

### Issue-specific utilities

The extended API keeps the native responses from Redmine's issue endpoints while adding a couple of quality-of-life options:

- Suppress notifications when creating or updating issues by passing `notify=false` (or `send_notification=0`). The request is still fully validated. Only that request is affected: its mail and its webhooks (Redmine 7.0 and later) are not sent, mail and webhooks of other users and requests are delivered as usual. On the core path `notify` is not a parameter and changes nothing.
- Suppress notifications when creating or deleting issue relations by passing `notify=false` (or `send_notification=0`) on relation endpoints. See the [core Redmine relations API](https://www.redmine.org/projects/redmine/wiki/Rest_issuerelations) for the base payloads.
- Preserve history when migrating data by explicitly setting `author_id`, `created_on`, `updated_on`, or `closed_on` on issues. These overrides are only applied for admin users routed through `/extended_api`, and automatic timestamp updates are disabled for the request to keep the supplied values intact.
- Preserve journal provenance when importing by supplying `journal[created_on]`,`journal[user_id]`, `journal[updated_on]`, or `journal[updated_by_id]` in extended issue requests. Admin-only overrides are applied to the generated journal entry while temporarily disabling journal timestamp updates to respect the provided values.
- Override values that cannot be stored are refused with `422` and nothing is saved: a time that does not parse (`"Created is invalid"`) or a user id that does not exist (`"Author is invalid"`, `"User is invalid"`).
- Successful issue updates that create a journal entry return the journal payload when routed through `/extended_api`, making it easy to confirm the resulting notes and metadata.
- Leave no trace of technical post-processing by passing `skip_journal=true` (or `1`, `yes`, `on`; top-level, next to `notify`, in the query string or the JSON body). Admin only, `/extended_api` only; everything else of the request behaves as without it (validations, the overrides above, `notify=false`). While it is set:
  - an issue create or update stores no journal (the update answers `204`), a parent gets no "Subtask added", creating or deleting a relation stores no journal on either issue, and no watcher is added through a journal;
  - every issue the request saves keeps its `updated_on` (the issue it updates, a parent, a rescheduled issue), unless the request sends its own `updated_on` override, which wins;
  - `PUT /extended_api/journals/:id.json` changes the notes but keeps the journal's `updated_on` and `updated_by`, so it is not shown as edited.

  A non-admin sending it gets `403` (`"You are not authorized to access this page."`) and nothing is changed. An issue update with `skip_journal` and `notes` (or `private_notes`) is refused with `422` (`"Notes is invalid"`): notes live in a journal and would be lost. `skip_journal=false`/`0` is the normal request. On the core path the parameter changes nothing.

### Imported issue history

`POST /extended_api/issues/:id/history.json` writes imported status, assignee and priority changes as journals with their own user and time, without saving the issue. Admin only (`403` for anyone else, `401` without credentials), `/extended_api` only (`404` on the core path), JSON only.

- Each journal is stored with `notes` empty, not private, `updated_on` = `created_on` and no `updated_by` (not shown as edited). Journals and details are written with `insert_all`, so no callback runs: no watcher is added, no mail, no webhook, no job of another plugin.
- The issue is not saved: `updated_on`, `closed_on`, `status_id` and its watchers stay as they are. Redmine shows the history ordered by `created_on`, then `id`, so the changes appear at their own time between existing journals.
- Details: `property` `attr` with `prop_key` `status_id`, `assigned_to_id` or `priority_id`; the values are ids of an existing status, user or group, or priority. `old_value` may be `null`; `value` only for `assigned_to_id` (unassigned).
- `attachments` (optional): uploads from `/extended_api/uploads.json` attached to the issue with the given `author_id` and `created_on` (and `filename`, `content_type`, `description`), with no journal.
- An issue in an archived project is refused with `403`; a closed project is accepted (an import may close its projects first).
- Refused with `422` and nothing stored: an empty `journals` list, a journal without details, another property or key, an id that does not exist, an unknown `user_id`, an unparseable `created_on`, any `notes` or `private_notes` (other than `false`), an unknown or already attached upload token, an unknown attachment author or time, an attachment filename, content type or description over 255 characters.
- Answer `201`: `{"journal_ids": [...], "attachment_ids": [...]}`, journal ids in the order sent.
- Redmine's "last updated by" is the user of the journal with the highest id: journals written by this endpoint after newer comments make their user the last updater.

```bash
curl -X POST -H "Content-Type: application/json" -H "X-Redmine-API-Key: <admin token>" \
  -d '{"journals":[{"user_id":12,"created_on":"2024-03-01T10:15:00Z","details":[
        {"property":"attr","prop_key":"status_id","old_value":"1","value":"3"},
        {"property":"attr","prop_key":"assigned_to_id","old_value":null,"value":"12"}]}],
       "attachments":[{"token":"<from /extended_api/uploads.json>","filename":"jira-history.json",
        "content_type":"application/json","description":"Jira history","author_id":12,"created_on":"2024-05-02T08:00:00Z"}]}' \
  https://redmine.example.com/extended_api/issues/123/history.json
# 201 {"journal_ids":[456],"attachment_ids":[789]}
```

### Attachment-specific utilities

- Preserve uploader history on imported files by supplying `author_id` and/or `created_on` in `/extended_api/uploads` requests. Overrides are limited to admin users and keep the provided timestamp intact by disabling automatic timestamp updates for the request. Values that cannot be stored are refused with `422`, as for issues.

#### Real-world examples for issues and journals

- Import a closed issue while preserving the original author and timestamps and suppressing outbound mail:

  ```bash
  curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: <token>" \
    -d '{"issue":{"project_id":1,"tracker_id":2,"status_id":5,"subject":"Legacy outage record","description":"Backfilled from the legacy tracker","author_id":7,"created_on":"2023-11-02T08:15:00Z","updated_on":"2023-11-04T17:40:00Z","closed_on":"2023-11-04T17:40:00Z"},"notify":false}' \
    https://redmine.example.com/extended_api/issues.json
  ```

- Add an imported journal entry to an existing issue, keep the original editor and timestamp, and avoid triggering notifications:

  ```bash
  curl -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: <token>" \
    -d '{"issue":{"notes":"Imported worklog from JIRA","journal":{"user_id":7,"updated_by_id":7,"created_on":"2023-12-01T11:00:00Z","updated_on":"2023-12-01T12:00:00Z"}},"notify":false}' \
    https://redmine.example.com/extended_api/issues/123.json
  ```

  ```json
  {
    "extended_api": {
      "mode": "extended",
      "fallback_to_native": false
    },
    "journal": {
      "id": 456,
      "issue_id": 123,
      "notes": "Imported worklog from JIRA",
      "created_on": "2023-12-01T11:00:00Z",
      "private_notes": false,
      "user": {
        "id": 7,
        "name": "Jane Doe"
      },
      "details": []
    }
  }
  ```

- Second pass of an import: rewrite the description, set the parent and link two issues, then rewrite an imported comment, without a journal, an "Edited" mark or a new `updated_on`:

  ```bash
  curl -X PUT -H "Content-Type: application/json" -H "X-Redmine-API-Key: <admin token>" \
    -d '{"issue":{"description":"See #124","parent_issue_id":120},"notify":false,"skip_journal":true}' \
    https://redmine.example.com/extended_api/issues/123.json            # 204
  curl -X POST -H "Content-Type: application/json" -H "X-Redmine-API-Key: <admin token>" \
    -d '{"relation":{"issue_to_id":124,"relation_type":"relates"},"notify":false,"skip_journal":true}' \
    https://redmine.example.com/extended_api/issues/123/relations.json  # 201
  curl -X PUT -H "Content-Type: application/json" -H "X-Redmine-API-Key: <admin token>" \
    -d '{"journal":{"notes":"Imported comment, see #124"},"skip_journal":true}' \
    https://redmine.example.com/extended_api/journals/456.json          # 204
  ```

- Create a relation without notifying watchers (extended API variant of the [core relations endpoint](https://www.redmine.org/projects/redmine/wiki/Rest_issuerelations)):

  ```bash
  curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: <token>" \
    -d '{"relation":{"issue_to_id":456,"relation_type":"relates"},"notify":false}' \
    https://redmine.example.com/extended_api/issues/123/relations.json
  ```

- Upload an attachment while preserving the original uploader and timestamp (admin users only):

  ```bash
  curl --globoff -X POST \
    -H "Content-Type: application/octet-stream" \
    -H "X-Redmine-API-Key: <token>" \
    --data-binary "@legacy-log.txt" \
    "https://redmine.example.com/extended_api/uploads.json?filename=legacy-log.txt&attachment[author_id]=7&attachment[created_on]=2023-11-02T08:15:00.509723Z"
  ```

  ```bash
  curl -X POST \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: <token>" \
    -d '{
    "issue": {
    "project_id": 1,
    "tracker_id": 3,
    "status_id": 5,
    "subject": "Legacy outage record with attachment - admin",
    "description": "Backfilled from the legacy tracker, attachment included",
    "author_id": 9,
    "assigned_to_id": 6,
    "created_on": "2023-11-02T08:15:00Z",
    "start_date": "2023-11-03",
    "updated_on": "2023-11-04T17:40:00Z",
    "closed_on": "2023-11-04T17:40:00Z",
    "uploads": [
    {
    "token": "<upload_toke>",
    "filename": "legacy-log.txt",
    "content_type": "text/plain"
    }
    ]
    },
    "notify": false
    }' \
  https://redmine.example.com/extended_api/issues.json
  ```     

  ```bash  
  curl -X PATCH \
    -H "Content-Type: application/json" \
    -H "X-Redmine-API-Key: <token>" \
    -d '{
    "issue": {
    "notes": "Imported worklog from JIRA: admin, attachment included",
    "journal": {
    "user_id": 9,
    "updated_by_id": 9,
    "created_on": "2023-12-01T11:00:00Z",
    "updated_on": "2023-12-01T12:00:00Z"
    },
    "uploads": [
    {
    "token": "<upload_toke>"",
    "filename": "legacy-log.txt",
    "content_type": "text/plain"
    }
    ]
    },
    "notify": false
    }' \
    https://redmine.example.com/extended_api/issues/90.json
  ```

### Availability legend

The reference tables below use the following terms:

- **Core (proxy)** – the operation already exists in Redmine and is simply proxied under `/extended_api`.
- **Core & Extended** – the operation already exists in Redmine and has been enhanced under `/extended_api`.
- **Extended only (new)** – the operation is exposed exclusively by this plugin. Core Redmine does not ship a REST equivalent.

## Extended endpoint reference

All paths require either `.json` or `.xml` and the usual authentication headers. The `Core Redmine` column lists the public path when one exists.

### Issue statuses

| Operation           | Method(s) | Extended path                               | Availability        | Notes                                                                                 |
|---------------------|-----------|---------------------------------------------|---------------------|---------------------------------------------------------------------------------------|
| List issue statuses | GET       | `/extended_api/issue_statuses.{format}`     | Core (proxy)        | Returns the catalog of statuses with `is_closed`, `default_done_ratio`, etc.          |
| Show issue status   | GET       | `/extended_api/issue_statuses/:id.{format}` | Extended only (new) | Retrieves a single status by id.                                                      |
| Create issue status | POST      | `/extended_api/issue_statuses.{format}`     | Extended only (new) | Payload under `issue_status` (`name`, `is_closed`, `position`, `default_done_ratio`). |
| Update issue status | PUT/PATCH | `/extended_api/issue_statuses/:id.{format}` | Extended only (new) | Accepts the same attributes as create.                                                |
| Delete issue status | DELETE    | `/extended_api/issue_statuses/:id.{format}` | Extended only (new) | Fails if the status is still referenced by issues or workflows.                       |

### Trackers

| Operation      | Method(s) | Extended path                         | Availability        | Notes                                                                                                                                   |
|----------------|-----------|---------------------------------------|---------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| List trackers  | GET       | `/extended_api/trackers.{format}`     | Core (proxy)        | Includes metadata such as `default_status` and enabled fields.                                                                          |
| Show tracker   | GET       | `/extended_api/trackers/:id.{format}` | Extended only (new) | Retrieves the tracker definition.                                                                                                       |
| Create tracker | POST      | `/extended_api/trackers.{format}`     | Extended only (new) | Payload under `tracker` (`name`, `default_status_id`, `core_fields`, `custom_field_ids`, `project_ids`, optional `copy_workflow_from`). |
| Update tracker | PUT/PATCH | `/extended_api/trackers/:id.{format}` | Extended only (new) | Accepts the same attributes as create.                                                                                                  |
| Delete tracker | DELETE    | `/extended_api/trackers/:id.{format}` | Extended only (new) | Cannot remove trackers still referenced by issues.                                                                                      |

### Roles

| Operation   | Method(s) | Extended path                      | Availability        | Notes                                                                                        |
|-------------|-----------|------------------------------------|---------------------|----------------------------------------------------------------------------------------------|
| List roles  | GET       | `/extended_api/roles.{format}`     | Core (proxy)        | Includes permissions, managed roles, and visibility flags.                                   |
| Show role   | GET       | `/extended_api/roles/:id.{format}` | Core (proxy)        | Retrieves the full role definition.                                                          |
| Create role | POST      | `/extended_api/roles.{format}`     | Extended only (new) | Payload under `role` (`name`, `permissions`, `managed_role_ids`, visibility settings, etc.). |
| Update role | PUT/PATCH | `/extended_api/roles/:id.{format}` | Extended only (new) | Accepts the same attributes as create.                                                       |
| Delete role | DELETE    | `/extended_api/roles/:id.{format}` | Extended only (new) | Requires admin rights; fails if the role is still assigned.                                  |

### Custom fields

| Operation           | Method(s) | Extended path                              | Availability        | Notes                                                                           |
|---------------------|-----------|--------------------------------------------|---------------------|---------------------------------------------------------------------------------|
| List custom fields  | GET       | `/extended_api/custom_fields.{format}`     | Core (proxy)        | Returns every custom field with permitted attributes.                           |
| Show custom field   | GET       | `/extended_api/custom_fields/:id.{format}` | Extended only (new) | Includes field format, visibility, possible values, trackers, etc.              |
| Create custom field | POST      | `/extended_api/custom_fields.{format}`     | Extended only (new) | Provide the type (e.g. `IssueCustomField`) and attributes under `custom_field`; without a valid type: `422`. |
| Update custom field | PUT/PATCH | `/extended_api/custom_fields/:id.{format}` | Extended only (new) | Supports mass updates of trackers, roles, visibility, and plugin attributes.    |
| Delete custom field | DELETE    | `/extended_api/custom_fields/:id.{format}` | Extended only (new) | Removes the field; follows the same validations as the UI.                      |

### Enumerations

| Operation          | Method(s) | Extended path                             | Availability        | Notes                                                                      |
|--------------------|-----------|-------------------------------------------|---------------------|----------------------------------------------------------------------------|
| List enumerations  | GET       | `/extended_api/enumerations.{format}`     | Core & Extended     | Use `?type=` to filter (e.g. `time_entry_activities`, `issue_priorities`). |
| Show enumeration   | GET       | `/extended_api/enumerations/:id.{format}` | Extended only (new) | Retrieves a single enumeration record.                                     |
| Create enumeration | POST      | `/extended_api/enumerations.{format}`     | Extended only (new) | Payload under `enumeration` (`type`, `name`, `active`, `position`, etc.).  |
| Update enumeration | PUT/PATCH | `/extended_api/enumerations/:id.{format}` | Extended only (new) | Accepts the same attributes as create.                                     |
| Delete enumeration | DELETE    | `/extended_api/enumerations/:id.{format}` | Extended only (new) | Supports `reassign_to_id` when reassigning dependent records.              |

### Depending on custom field options (optional)

When the [`redmine_depending_custom_fields`](https://github.com/jcatrysse/redmine_depending_custom_fields) plugin is installed, the extended API exposes additional attributes for managing value dependencies. These attributes are not available in core Redmine.

| Operation                                   | Method(s)      | Extended path                                | Availability        | Notes                                                                                                              |
|---------------------------------------------|----------------|----------------------------------------------|---------------------|--------------------------------------------------------------------------------------------------------------------|
| Manage dependency metadata on custom fields | POST/PUT/PATCH | `/extended_api/custom_fields(/:id).{format}` | Extended only (new) | Accepts `value_dependencies`, `default_value_dependencies`, `hide_when_disabled`, etc., mirroring the plugin's UI. |

## JSON write examples

The new administrative writing endpoints accept JSON or XML payloads. The snippets below provide end-to-end examples for the most common mutations, including payloads for [`redmine_depending_custom_fields`](https://github.com/jcatrysse/redmine_depending_custom_fields). Replace `https://redmine.example.com` and `<token>` with values from your environment.

### Issue statuses

```bash
# Create a new issue status
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"issue_status":{"name":"QA Review","is_closed":false,"position":7,"default_done_ratio":50}}' \
  https://redmine.example.com/extended_api/issue_statuses.json

# Update an existing issue status and close it
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"issue_status":{"name":"Deployed","is_closed":true,"default_done_ratio":100}}' \
  https://redmine.example.com/extended_api/issue_statuses/9.json
```

### Trackers

```bash
# Create a tracker that inherits core fields and applies to specific projects
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"tracker":{"name":"Deployment","default_status_id":1,"core_fields":["assigned_to_id","fixed_version_id"],"project_ids":[1,3]}}' \
  https://redmine.example.com/extended_api/trackers.json

# Update a tracker, add a project and extend the core fields
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"tracker":{"project_ids":[1,3,5],"core_fields":["assigned_to_id","fixed_version_id","category_id"]}}' \
  https://redmine.example.com/extended_api/trackers/5.json
```

### Enumerations

```bash
# Create a time entry activity enumeration
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"enumeration":{"type":"TimeEntryActivity","name":"Pair programming","active":true}}' \
  https://redmine.example.com/extended_api/enumerations.json

# Delete an enumeration and reassign existing records
curl -X DELETE \
  -H "X-Redmine-API-Key: <token>" \
  "https://redmine.example.com/extended_api/enumerations/12.json?reassign_to_id=8"
```

### Roles

```bash
# Create a role with custom permissions and managed roles
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"role":{"name":"Deployment manager","assignable":true,"permissions":["manage_versions","manage_members"],"managed_role_ids":[2,3]}}' \
  https://redmine.example.com/extended_api/roles.json

# Update a role to toggle a permission and default membership
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"role":{"permissions":["edit_issues","manage_public_queries"],"settings":{"users_visibility":"members_of_visible_projects"}}}' \
  https://redmine.example.com/extended_api/roles/6.json
```

### Custom fields

List-based custom fields (`field_format: "list"`) still use the legacy `possible_values` array of strings. Enumeration-based custom fields (`field_format: "enumeration"`) are backed by API-managed `enumerations` objects instead. Each entry can set `name`, `active`, and `position`; include the `id` when updating to preserve identities, and pass the enumeration id as the `default_value` when you want the field to preselect one of the options.

```bash
# Create a project custom field with explicit possible values
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"type":"ProjectCustomField","custom_field":{"name":"Deployment region","field_format":"list","possible_values":["EU","US","APAC"],"is_required":true}}' \
  https://redmine.example.com/extended_api/custom_fields.json

# Create an enumeration custom field backed by API-managed options
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"type":"IssueCustomField","custom_field":{"name":"Root cause","field_format":"enumeration","enumerations":[{"name":"Configuration"},{"name":"Code"},{"name":"Third-party"}],"multiple":true}}' \
  https://redmine.example.com/extended_api/custom_fields.json

# Update an issue custom field with new trackers and roles
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"custom_field":{"tracker_ids":[1,4],"role_ids":[3,5],"visible":false}}' \
  https://redmine.example.com/extended_api/custom_fields/18.json

# Update enumeration custom field options and keep existing ids stable
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"custom_field":{"enumerations":[{"id":12,"name":"Configuration","active":true},{"id":14,"name":"Third-party vendor","active":true},{"id":15,"name":"Process","active":false}],"default_value":"14"}}' \
  https://redmine.example.com/extended_api/custom_fields/18.json
```
