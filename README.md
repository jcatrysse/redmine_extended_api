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

1. Clone this repository into your Redmine plugins directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/jcatrysse/redmine_extended_api.git
   ```
2. Restart Redmine.

No database migrations are required at this stage.

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
| Create custom field | POST      | `/extended_api/custom_fields.{format}`     | Extended only (new) | Provide the type (e.g. `IssueCustomField`) and attributes under `custom_field`. |
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

```bash
# Create a project custom field with explicit possible values
curl -X POST \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"type":"ProjectCustomField","custom_field":{"name":"Deployment region","field_format":"list","possible_values":["EU","US","APAC"],"is_required":true}}' \
  https://redmine.example.com/extended_api/custom_fields.json

# Update an issue custom field with new trackers and roles
curl -X PATCH \
  -H "Content-Type: application/json" \
  -H "X-Redmine-API-Key: <token>" \
  -d '{"custom_field":{"tracker_ids":[1,4],"role_ids":[3,5],"visible":false}}' \
  https://redmine.example.com/extended_api/custom_fields/18.json
```
