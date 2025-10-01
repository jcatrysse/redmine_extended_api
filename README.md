# Redmine Extended API

**ATTENTION: ALPHA STAGE**

This plugin extends the default Redmine API by providing a dedicated endpoint that mirrors the behaviour of the core Redmine REST API.
The goal of this first iteration is to offer a safe playground for new capabilities (POST/PUT/DELETE and plugin-specific functionality) without interfering with the built-in endpoints.

## Features

- Transparent proxy for all REST API calls that exist in Redmine.
- New isolated base path (`/extended_api`) to avoid conflicts with the core API.
- Works on both Redmine 5.x and 6.x installations.

Future releases will start enabling write operations and expose endpoints for complementary plugins such as [`redmine_depending_custom_fields`](https://github.com/jcatrysse/redmine_depending_custom_fields) and [`redmine_stealth`](https://github.com/jcatrysse/redmine_stealth).

## Installation

1. Clone this repository into your Redmine plugins directory:
   ```bash
   cd /path/to/redmine/plugins
   git clone https://github.com/jcatrysse/redmine_extended_api.git
   ```
2. Restart Redmine.

No database migrations are required at this stage.

## Usage

All REST API calls that ship with Redmine remain available at their original paths. The plugin adds a drop-in replacement under `/extended_api` where the behaviour, payloads and permissions are identical because every request is proxied back to the core Rails stack.

> **Note**
> Only controllers/actions that support API authentication in Redmine are exposed through the proxy. Requests targeting HTML-only controllers (e.g. `/my/page`) will respond with `404` from `/extended_api` because those routes are intentionally outside of scope.

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

### Endpoint reference (mirrors Redmine)

Below you will find the list of resources that expose API endpoints in Redmine 6.1. Each operation behaves exactly the same way when called through `/extended_api`.

#### Issues

| Operation    | Method(s) | Core path              | Extended path                       | Notes                                                                                                                            |
|--------------|-----------|------------------------|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------------|
| List issues  | GET       | `/issues.{format}`     | `/extended_api/issues.{format}`     | Supports filters such as `status_id`, `project_id`, `offset`, `limit`, `sort`, `query_id`, etc.                                  |
| Show issue   | GET       | `/issues/:id.{format}` | `/extended_api/issues/:id.{format}` | Includes journals, attachments, relations depending on permissions and params.                                                   |
| Create issue | POST      | `/issues.{format}`     | `/extended_api/issues.{format}`     | Provide attributes under the `issue` object (e.g. `project_id`, `tracker_id`, `subject`, `description`, custom fields, uploads). |
| Update issue | PUT/PATCH | `/issues/:id.{format}` | `/extended_api/issues/:id.{format}` | Send partial or full updates under the `issue` object, exactly like the core API.                                                |
| Delete issue | DELETE    | `/issues/:id.{format}` | `/extended_api/issues/:id.{format}` | Requires the same permissions as the core API.                                                                                   |

#### Issue relations

| Operation                   | Method(s) | Core path                              | Extended path                                       | Notes                                                                 |
|-----------------------------|-----------|----------------------------------------|-----------------------------------------------------|-----------------------------------------------------------------------|
| List relations for an issue | GET       | `/issues/:issue_id/relations.{format}` | `/extended_api/issues/:issue_id/relations.{format}` | Accepts `issue_to_id` and `relations` filtering params.               |
| Show relation               | GET       | `/relations/:id.{format}`              | `/extended_api/relations/:id.{format}`              | Retrieves a single relation record.                                   |
| Create relation             | POST      | `/issues/:issue_id/relations.{format}` | `/extended_api/issues/:issue_id/relations.{format}` | Body under `relation` (e.g. `issue_to_id`, `relation_type`, `delay`). |
| Delete relation             | DELETE    | `/relations/:id.{format}`              | `/extended_api/relations/:id.{format}`              | Removes a relation.                                                   |

#### Watchers

| Operation                    | Method(s) | Core path                                      | Extended path                                               | Notes                                                                      |
|------------------------------|-----------|------------------------------------------------|-------------------------------------------------------------|----------------------------------------------------------------------------|
| Add watchers to an issue     | POST      | `/issues/:issue_id/watchers.{format}`          | `/extended_api/issues/:issue_id/watchers.{format}`          | Provide `user_id`, `user_ids`, `watcher[user_id]`, or `watcher[user_ids]`. |
| Remove watcher from an issue | DELETE    | `/issues/:issue_id/watchers/:user_id.{format}` | `/extended_api/issues/:issue_id/watchers/:user_id.{format}` | Removes a single watcher.                                                  |

#### Journals

| Operation          | Method(s) | Core path                | Extended path                         | Notes                                               |
|--------------------|-----------|--------------------------|---------------------------------------|-----------------------------------------------------|
| Edit journal notes | PUT/PATCH | `/journals/:id.{format}` | `/extended_api/journals/:id.{format}` | Payload under `journal` (`notes`, `private_notes`). |

#### Time entries

| Operation                       | Method(s) | Core path                                     | Extended path                                              | Notes                                                                                                    |
|---------------------------------|-----------|-----------------------------------------------|------------------------------------------------------------|----------------------------------------------------------------------------------------------------------|
| List time entries               | GET       | `/time_entries.{format}`                      | `/extended_api/time_entries.{format}`                      | Supports `project_id`, `issue_id`, date filters, `offset`, `limit`.                                      |
| List time entries for an issue  | GET       | `/issues/:issue_id/time_entries.{format}`     | `/extended_api/issues/:issue_id/time_entries.{format}`     | Same behaviour as core.                                                                                  |
| List time entries for a project | GET       | `/projects/:project_id/time_entries.{format}` | `/extended_api/projects/:project_id/time_entries.{format}` | Same filters as global list.                                                                             |
| Show time entry                 | GET       | `/time_entries/:id.{format}`                  | `/extended_api/time_entries/:id.{format}`                  | —                                                                                                        |
| Create time entry               | POST      | `/time_entries.{format}`                      | `/extended_api/time_entries.{format}`                      | Body under `time_entry` (e.g. `project_id`, `issue_id`, `spent_on`, `hours`, `activity_id`, `comments`). |
| Update time entry               | PUT/PATCH | `/time_entries/:id.{format}`                  | `/extended_api/time_entries/:id.{format}`                  | Partial updates allowed.                                                                                 |
| Delete time entry               | DELETE    | `/time_entries/:id.{format}`                  | `/extended_api/time_entries/:id.{format}`                  | —                                                                                                        |

#### Projects

| Operation         | Method(s) | Core path                          | Extended path                                   | Notes                                                                                         |
|-------------------|-----------|------------------------------------|-------------------------------------------------|-----------------------------------------------------------------------------------------------|
| List projects     | GET       | `/projects.{format}`               | `/extended_api/projects.{format}`               | Supports `offset`, `limit`, `include=trackers,issue_categories,enabled_modules`.              |
| Show project      | GET       | `/projects/:id.{format}`           | `/extended_api/projects/:id.{format}`           | `:id` accepts identifier or internal id.                                                      |
| Create project    | POST      | `/projects.{format}`               | `/extended_api/projects.{format}`               | Payload under `project` (e.g. `name`, `identifier`, `enabled_module_names`, `custom_fields`). |
| Update project    | PUT/PATCH | `/projects/:id.{format}`           | `/extended_api/projects/:id.{format}`           | Same payload structure as create.                                                             |
| Delete project    | DELETE    | `/projects/:id.{format}`           | `/extended_api/projects/:id.{format}`           | Soft-delete identical to core API.                                                            |
| Archive project   | POST/PUT  | `/projects/:id/archive.{format}`   | `/extended_api/projects/:id/archive.{format}`   | Requires admin permissions.                                                                   |
| Unarchive project | POST/PUT  | `/projects/:id/unarchive.{format}` | `/extended_api/projects/:id/unarchive.{format}` | —                                                                                             |
| Close project     | POST/PUT  | `/projects/:id/close.{format}`     | `/extended_api/projects/:id/close.{format}`     | —                                                                                             |
| Reopen project    | POST/PUT  | `/projects/:id/reopen.{format}`    | `/extended_api/projects/:id/reopen.{format}`    | —                                                                                             |

#### Project memberships

| Operation         | Method(s) | Core path                                    | Extended path                                             | Notes                                                                                |
|-------------------|-----------|----------------------------------------------|-----------------------------------------------------------|--------------------------------------------------------------------------------------|
| List members      | GET       | `/projects/:project_id/memberships.{format}` | `/extended_api/projects/:project_id/memberships.{format}` | Supports pagination with `offset`/`limit`.                                           |
| Show membership   | GET       | `/memberships/:id.{format}`                  | `/extended_api/memberships/:id.{format}`                  | —                                                                                    |
| Create membership | POST      | `/projects/:project_id/memberships.{format}` | `/extended_api/projects/:project_id/memberships.{format}` | Provide `membership[user_id]` or `membership[user_ids]` plus `membership[role_ids]`. |
| Update membership | PUT/PATCH | `/memberships/:id.{format}`                  | `/extended_api/memberships/:id.{format}`                  | Supply new `membership[role_ids]`.                                                   |
| Delete membership | DELETE    | `/memberships/:id.{format}`                  | `/extended_api/memberships/:id.{format}`                  | —                                                                                    |

#### Versions

| Operation             | Method(s) | Core path                                 | Extended path                                          | Notes                                                         |
|-----------------------|-----------|-------------------------------------------|--------------------------------------------------------|---------------------------------------------------------------|
| List project versions | GET       | `/projects/:project_id/versions.{format}` | `/extended_api/projects/:project_id/versions.{format}` | Also accessible via `/versions.{format}?project_id=...`.      |
| Show version          | GET       | `/versions/:id.{format}`                  | `/extended_api/versions/:id.{format}`                  | —                                                             |
| Create version        | POST      | `/projects/:project_id/versions.{format}` | `/extended_api/projects/:project_id/versions.{format}` | Body under `version` (name, status, sharing, due_date, etc.). |
| Update version        | PUT/PATCH | `/versions/:id.{format}`                  | `/extended_api/versions/:id.{format}`                  | —                                                             |
| Delete version        | DELETE    | `/versions/:id.{format}`                  | `/extended_api/versions/:id.{format}`                  | —                                                             |

#### Issue categories

| Operation       | Method(s) | Core path                                         | Extended path                                                  | Notes                                                   |
|-----------------|-----------|---------------------------------------------------|----------------------------------------------------------------|---------------------------------------------------------|
| List categories | GET       | `/projects/:project_id/issue_categories.{format}` | `/extended_api/projects/:project_id/issue_categories.{format}` | —                                                       |
| Show category   | GET       | `/issue_categories/:id.{format}`                  | `/extended_api/issue_categories/:id.{format}`                  | —                                                       |
| Create category | POST      | `/projects/:project_id/issue_categories.{format}` | `/extended_api/projects/:project_id/issue_categories.{format}` | Body under `issue_category` (`name`, `assigned_to_id`). |
| Update category | PUT/PATCH | `/issue_categories/:id.{format}`                  | `/extended_api/issue_categories/:id.{format}`                  | —                                                       |
| Delete category | DELETE    | `/issue_categories/:id.{format}`                  | `/extended_api/issue_categories/:id.{format}`                  | Optional `reassign_to_id` parameter.                    |

#### Users

| Operation   | Method(s) | Core path             | Extended path                      | Notes                                                      |
|-------------|-----------|-----------------------|------------------------------------|------------------------------------------------------------|
| List users  | GET       | `/users.{format}`     | `/extended_api/users.{format}`     | Supports `status`, `name`, `group_id`, `offset`, `limit`.  |
| Show user   | GET       | `/users/:id.{format}` | `/extended_api/users/:id.{format}` | Accepts `:id` or `current` for the authenticated user.     |
| Create user | POST      | `/users.{format}`     | `/extended_api/users.{format}`     | Payload under `user` and optional `send_information` flag. |
| Update user | PUT/PATCH | `/users/:id.{format}` | `/extended_api/users/:id.{format}` | Same payload as create.                                    |
| Delete user | DELETE    | `/users/:id.{format}` | `/extended_api/users/:id.{format}` | —                                                          |

#### Groups

| Operation              | Method(s) | Core path                             | Extended path                                      | Notes                             |
|------------------------|-----------|---------------------------------------|----------------------------------------------------|-----------------------------------|
| List groups            | GET       | `/groups.{format}`                    | `/extended_api/groups.{format}`                    | Supports pagination.              |
| Show group             | GET       | `/groups/:id.{format}`                | `/extended_api/groups/:id.{format}`                | —                                 |
| Create group           | POST      | `/groups.{format}`                    | `/extended_api/groups.{format}`                    | Body under `group` (`name` etc.). |
| Update group           | PUT/PATCH | `/groups/:id.{format}`                | `/extended_api/groups/:id.{format}`                | —                                 |
| Delete group           | DELETE    | `/groups/:id.{format}`                | `/extended_api/groups/:id.{format}`                | —                                 |
| Add users to group     | POST      | `/groups/:id/users.{format}`          | `/extended_api/groups/:id/users.{format}`          | Provide `user_id` or `user_ids`.  |
| Remove user from group | DELETE    | `/groups/:id/users/:user_id.{format}` | `/extended_api/groups/:id/users/:user_id.{format}` | —                                 |

#### Roles

| Operation  | Method(s) | Core path             | Extended path                      | Notes                      |
|------------|-----------|-----------------------|------------------------------------|----------------------------|
| List roles | GET       | `/roles.{format}`     | `/extended_api/roles.{format}`     | —                          |
| Show role  | GET       | `/roles/:id.{format}` | `/extended_api/roles/:id.{format}` | Includes permissions list. |

#### Trackers

| Operation     | Method(s) | Core path            | Extended path                     | Notes                                                                     |
|---------------|-----------|----------------------|-----------------------------------|---------------------------------------------------------------------------|
| List trackers | GET       | `/trackers.{format}` | `/extended_api/trackers.{format}` | Includes fields like `default_status` and `custom_fields` when requested. |

#### Issue statuses

| Operation           | Method(s) | Core path                  | Extended path                           | Notes |
|---------------------|-----------|----------------------------|-----------------------------------------|-------|
| List issue statuses | GET       | `/issue_statuses.{format}` | `/extended_api/issue_statuses.{format}` | —     |

#### Custom fields

| Operation          | Method(s) | Core path                 | Extended path                          | Notes                                                                |
|--------------------|-----------|---------------------------|----------------------------------------|----------------------------------------------------------------------|
| List custom fields | GET       | `/custom_fields.{format}` | `/extended_api/custom_fields.{format}` | Returns all custom fields, including available formats and trackers. |

#### Enumerations

| Operation         | Method(s) | Core path                | Extended path                         | Notes                                                                      |
|-------------------|-----------|--------------------------|---------------------------------------|----------------------------------------------------------------------------|
| List enumerations | GET       | `/enumerations.{format}` | `/extended_api/enumerations.{format}` | Use `?type=` to filter (e.g. `time_entry_activities`, `issue_priorities`). |

#### News

| Operation   | Method(s) | Core path                             | Extended path                                      | Notes                                                        |
|-------------|-----------|---------------------------------------|----------------------------------------------------|--------------------------------------------------------------|
| List news   | GET       | `/news.{format}`                      | `/extended_api/news.{format}`                      | Supports `project_id`, `offset`, `limit`.                    |
| Show news   | GET       | `/news/:id.{format}`                  | `/extended_api/news/:id.{format}`                  | Includes comments when available.                            |
| Create news | POST      | `/projects/:project_id/news.{format}` | `/extended_api/projects/:project_id/news.{format}` | Body under `news` (`title`, `description`, `summary`, etc.). |
| Update news | PUT/PATCH | `/news/:id.{format}`                  | `/extended_api/news/:id.{format}`                  | —                                                            |
| Delete news | DELETE    | `/news/:id.{format}`                  | `/extended_api/news/:id.{format}`                  | —                                                            |

#### Files & attachments

| Operation             | Method(s) | Core path                              | Extended path                                       | Notes                                                                                                                   |
|-----------------------|-----------|----------------------------------------|-----------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| List project files    | GET       | `/projects/:project_id/files.{format}` | `/extended_api/projects/:project_id/files.{format}` | Lists documents under the project “Files” module.                                                                       |
| Upload binary payload | POST      | `/uploads.{format}`                    | `/extended_api/uploads.{format}`                    | Send raw file in the request body; response contains `upload.token` for later association.                              |
| Attach uploaded file  | Any       | *(varies)*                             | *(varies)*                                          | Use the returned `token` in `uploads` arrays on issues, wiki pages, etc. Works identically under the extended endpoint. |
| Show attachment       | GET       | `/attachments/:id.{format}`            | `/extended_api/attachments/:id.{format}`            | Retrieves metadata; to download binary use `.download` path.                                                            |
| Download attachment   | GET       | `/attachments/download/:id`            | `/extended_api/attachments/download/:id`            | Streams file contents.                                                                                                  |
| Thumbnail             | GET       | `/attachments/thumbnail/:id(/:size)`   | `/extended_api/attachments/thumbnail/:id(/:size)`   | —                                                                                                                       |
| Update attachment     | PUT/PATCH | `/attachments/:id.{format}`            | `/extended_api/attachments/:id.{format}`            | Update filename, description, visibility.                                                                               |
| Delete attachment     | DELETE    | `/attachments/:id.{format}`            | `/extended_api/attachments/:id.{format}`            | —                                                                                                                       |

#### Wiki pages

| Operation          | Method(s) | Core path                                   | Extended path                                            | Notes                                                                         |
|--------------------|-----------|---------------------------------------------|----------------------------------------------------------|-------------------------------------------------------------------------------|
| List wiki pages    | GET       | `/projects/:project_id/wiki/index.{format}` | `/extended_api/projects/:project_id/wiki/index.{format}` | Returns the page tree for the project.                                        |
| Show wiki page     | GET       | `/projects/:project_id/wiki/:page.{format}` | `/extended_api/projects/:project_id/wiki/:page.{format}` | Append `?version=` to retrieve a specific version.                            |
| Update/create page | PUT/PATCH | `/projects/:project_id/wiki/:page.{format}` | `/extended_api/projects/:project_id/wiki/:page.{format}` | Body under `wiki_page` with `text`, `comments`, `version` (for edit locking). |
| Delete wiki page   | DELETE    | `/projects/:project_id/wiki/:page.{format}` | `/extended_api/projects/:project_id/wiki/:page.{format}` | Supports `?destroy_children=1` to remove descendants.                         |

#### Queries

| Operation          | Method(s) | Core path           | Extended path                    | Notes                                     |
|--------------------|-----------|---------------------|----------------------------------|-------------------------------------------|
| List saved queries | GET       | `/queries.{format}` | `/extended_api/queries.{format}` | Use `?project_id=` to scope to a project. |

#### Search

| Operation              | Method(s) | Core path          | Extended path                   | Notes                                                                                                                                       |
|------------------------|-----------|--------------------|---------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------|
| Search across entities | GET       | `/search.{format}` | `/extended_api/search.{format}` | Provide `q` plus optional `scope`, `all_words`, `titles_only`, `offset`, `limit`. Project-specific search: `/projects/:id/search.{format}`. |

#### Repositories (changesets)

| Operation               | Method(s) | Core path                                                                                  | Extended path                                                                                           | Notes                 |
|-------------------------|-----------|--------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|-----------------------|
| Link issue to changeset | POST      | `/projects/:project_id/repository/:repository_id/revisions/:rev/issues.{format}`           | `/extended_api/projects/:project_id/repository/:repository_id/revisions/:rev/issues.{format}`           | Body with `issue_id`. |
| Remove linked issue     | DELETE    | `/projects/:project_id/repository/:repository_id/revisions/:rev/issues/:issue_id.{format}` | `/extended_api/projects/:project_id/repository/:repository_id/revisions/:rev/issues/:issue_id.{format}` | —                     |

#### My account

| Operation                   | Method(s) | Core path              | Extended path                       | Notes                                              |
|-----------------------------|-----------|------------------------|-------------------------------------|----------------------------------------------------|
| Update current user profile | PUT/PATCH | `/my/account.{format}` | `/extended_api/my/account.{format}` | Same parameters as the HTML form (`user`, `pref`). |

This overview covers every controller action that exposes REST access in Redmine 6.1 (`accept_api_auth` in the upstream source). Whenever you extend or customise the upstream API, simply apply the same path transformation (`/extended_api/...`) to reach the mirrored behaviour.

## Development

Run the automated test suite with:

```bash
RAILS_ENV=test bundle exec rspec plugins/redmine_extended_api/spec
```

## Development roadmap

1. **Phase 1 (current)**: mirror of the Redmine 6.1 REST API at `/extended_api`.
2. **Phase 2**: progressively enable POST, PUT, PATCH and DELETE operations where missing.
3. **Phase 3**: expose API endpoints for depending on custom fields and allow enabling "stealth mode" to suppress e-mail notifications via API.

## Thank you

Many thanks to ChatGPT for helping to create this plugin.

## License

This plugin is released under the GNU GPL v3.
