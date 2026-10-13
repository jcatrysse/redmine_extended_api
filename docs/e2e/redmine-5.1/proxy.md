# proxy

Run 2026-10-13T14:29:37.732Z against http://127.0.0.1:3051.

| screenshot | user | URL | shows |
|---|---|---|---|
| ![](proxy-rest-api-on.png) | admin | `/settings?tab=api` | Administration > Settings > Integrations (API before Redmine 7): REST API turned on through the form |
| ![](proxy-same-as-core.png) | admin | `/settings?tab=api` | GET under /extended_api returns what the core path returns (JSON and XML), marked "native" |
| ![](proxy-permissions.png) | admin | `/settings?tab=api` | Under /extended_api the core permissions hold: the private project is refused to outsider (403) and anonymous (401) |
| ![](proxy-not-api.png) | admin | `/settings?tab=api` | HTML routes, a path without .json/.xml and unknown routes are refused under /extended_api with a JSON 404 |
| ![](proxy-rest-api-off.png) | admin | `/settings?tab=api` | REST API turned off |
| ![](proxy-rest-api-off-refused.png) | admin | `/settings?tab=api` | With the REST API off the credentials are ignored: /extended_api refuses the private project and writes with the same status as the core path |
