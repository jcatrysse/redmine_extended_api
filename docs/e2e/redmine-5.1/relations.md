# relations

Run 2026-10-13T14:29:46.913Z against http://127.0.0.1:3051.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](relations-create.png) | admin | `/settings?tab=api` | Manager (manage_issue_relations) relates two issues with notify=false (201) and reads the relation back |
| ![](relations-issue-page.png) | manager | `/issues/16` | The issue page shows "Blocks" the other issue |
| ![](relations-refused.png) | manager | `/issues/16` | Refusals as in core: reporter without manage_issue_relations and outsider (403), duplicate, unknown target, relation to itself (422) |
| ![](relations-delete.png) | manager | `/issues/16` | Manager deletes the relation with notify=false (204); it is gone (404) |
| ![](relations-issue-page-after.png) | manager | `/issues/16` | The issue page after the delete: no related issues left, the history shows add and delete of the relation |
