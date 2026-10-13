# trackers

Run 2026-10-13T14:31:09.450Z against http://127.0.0.1:3051.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](trackers-admin-crud.png) | admin | `/settings?tab=api` | Admin creates a tracker linked to e2e-project with workflow copied from Bug (201), updates its fields (200), shows it as XML |
| ![](trackers-admin-list.png) | admin | `/trackers` | Administration > Trackers lists the tracker created through the API |
| ![](trackers-admin-edit.png) | admin | `/trackers/5/edit` | Its edit form: the standard fields and the project set through the API |
| ![](trackers-in-project.png) | manager | `/projects/e2e-project/issues/new` | A member of e2e-project picks the new tracker: the form shows only the standard fields set through the API (assignee, due date) |
| ![](trackers-refused.png) | manager | `/projects/e2e-project/issues/new` | Refusals: blank and duplicate name (422), unknown id (404), non-admins (403), core path without show (404), tracker in use (422 with the core reason; from 6.1 on it names the projects) |
| ![](trackers-delete.png) | manager | `/projects/e2e-project/issues/new` | An unused tracker is deleted (204) and gone (404) |
