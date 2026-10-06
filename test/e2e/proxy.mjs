// The /extended_api proxy: every core REST endpoint answers under the prefix with
// the same data and the same permissions, HTML-only routes are refused, and the
// REST API setting is respected.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('proxy');
const { client, setApiSettings } = api;
const a = client(t);

await setApiSettings(t, { rest: true });
await t.shot('rest-api-on', 'Administration > Settings > Integrations: REST API turned on through the form');

// same data on the core path and under /extended_api
const core = a.expect(await a.call('GET', '/issues.json?project_id=e2e-project&status_id=*'), 200);
const ext = a.expect(await a.call('GET', '/extended_api/issues.json?project_id=e2e-project&status_id=*'), 200);
a.check(ext.mode === 'native', `proxy: x-redmine-extended-api is "${ext.mode}", expected native`);
a.check(core.json && ext.json && core.json.total_count === ext.json.total_count,
  `proxy: total_count differs, core ${core.json && core.json.total_count}, extended ${ext.json && ext.json.total_count}`);
a.expect(await a.call('GET', '/extended_api/projects/e2e-project.json'), 200);
a.expect(await a.call('GET', '/extended_api/projects/e2e-project/versions.xml'), 200);
a.expect(await a.call('GET', '/extended_api/users/current.json', { as: 'manager' }), 200);
await a.show('same-as-core', 'GET under /extended_api returns what the core path returns (JSON and XML), marked "native"');

// the permissions are the core ones
a.expect(await a.call('GET', '/extended_api/projects/e2e-private.json', { as: 'manager' }), 200, 'member of the private project');
a.expect(await a.call('GET', '/extended_api/projects/e2e-private.json', { as: 'outsider' }), 403, 'private project, no membership');
const anon = a.expect(await a.call('GET', '/extended_api/projects/e2e-private.json', { as: null }), 401, 'anonymous');
const outsiderIssues = a.expect(await a.call('GET', '/extended_api/issues.json?project_id=e2e-private', { as: 'outsider' }), 403);
a.check(!/E2E private/.test(outsiderIssues.text) && !/E2E private/.test(anon.text), 'proxy: private data leaked to a non-member');
a.expect(await a.call('GET', '/extended_api/issues/999999.json'), 404, 'unknown issue');
await a.show('permissions', 'Under /extended_api the core permissions hold: the private project is refused to outsider (403) and anonymous (401)');

// only API routes are proxied
const html = a.expect(await a.call('GET', '/extended_api/my/page'), 404, 'HTML route');
a.check(html.json && html.json.error === 'Not a REST API endpoint', `proxy: /my/page answer is ${html.text.slice(0, 100)}`);
a.expect(await a.call('GET', '/extended_api/projects/e2e-project'), 404, 'no format');
a.expect(await a.call('GET', '/extended_api/no/such/route.json'), 404, 'unknown route');
await a.show('not-api', 'HTML routes, a path without .json/.xml and unknown routes are refused under /extended_api with a JSON 404');

// the REST API setting is respected
await setApiSettings(t, { rest: false });
await t.shot('rest-api-off', 'REST API turned off');
// the credentials are ignored then, so the request is anonymous: public data only, the
// private project and writes are refused, exactly as on the core path
for (const [method, path, data] of [
  ['GET', '/projects/e2e-private.json'],
  ['GET', '/issues.json?project_id=e2e-private'],
  ['POST', '/issue_statuses.json', { issue_status: { name: 'Refused when off' } }],
]) {
  const c = await a.call(method, path, { as: 'manager', data });
  const x = await a.call(method, '/extended_api' + path, { as: 'manager', data });
  a.check(c.status >= 400 && x.status === c.status, `REST API off: ${method} ${path} core ${c.status}, extended ${x.status}`);
}
await a.show('rest-api-off-refused', 'With the REST API off the credentials are ignored: /extended_api refuses the private project and writes with the same status as the core path');
await setApiSettings(t, { rest: true });

await t.done();
