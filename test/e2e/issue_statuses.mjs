// Issue statuses through /extended_api: show, create, update, delete (extended
// only), admin only, validation errors, and the core path left untouched.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('issue-statuses');
const { client, setApiSettings } = api;
const a = client(t);
const name = `E2E status ${Date.now() % 1000000}`;

await setApiSettings(t, { rest: true });

const created = a.expect(await a.call('POST', '/extended_api/issue_statuses.json',
  { data: { issue_status: { name, is_closed: false, default_done_ratio: 50 } } }), 201);
const id = created.json && created.json.issue_status && created.json.issue_status.id;
a.check(created.mode === 'extended', `create: x-redmine-extended-api is "${created.mode}"`);
a.check(created.json && created.json.extended_api && created.json.extended_api.mode === 'extended', 'create: no extended_api block in the body');
a.expect(await a.call('GET', `/extended_api/issue_statuses/${id}.json`), 200);
const updated = a.expect(await a.call('PUT', `/extended_api/issue_statuses/${id}.json`,
  { data: { issue_status: { name: `${name} closed`, is_closed: true } } }), 200);
a.check(updated.json?.issue_status?.is_closed === true, 'update: is_closed not saved');
a.expect(await a.call('GET', `/extended_api/issue_statuses/${id}.xml`), 200);
await a.show('admin-crud', 'Admin creates (201), shows, updates (200) an issue status under /extended_api; JSON and XML, marked "extended"');

await t.login('admin');
await t.go('/issue_statuses');
a.check(await t.page.locator('table.list td', { hasText: `${name} closed` }).count() > 0, 'the status made through the API is not in Administration > Issue statuses');
await t.shot('admin-list', 'Administration > Issue statuses shows the status created and closed through the API');

// failure paths
a.expect(await a.call('POST', '/extended_api/issue_statuses.json', { data: { issue_status: { name: '' } } }), 422, 'blank name');
a.expect(await a.call('POST', '/extended_api/issue_statuses.json', { data: { issue_status: { name: `${name} closed` } } }), 422, 'duplicate name');
a.expect(await a.call('GET', '/extended_api/issue_statuses/999999.json'), 404, 'unknown id');
a.expect(await a.call('POST', '/extended_api/issue_statuses.json', { as: 'manager', data: { issue_status: { name: 'by manager' } } }), 403, 'not admin');
a.expect(await a.call('PUT', `/extended_api/issue_statuses/${id}.json`, { as: 'reporter', data: { issue_status: { name: 'by reporter' } } }), 403, 'not admin');
a.expect(await a.call('DELETE', `/extended_api/issue_statuses/${id}.json`, { as: 'outsider' }), 403, 'not admin');
a.expect(await a.call('GET', `/extended_api/issue_statuses/${id}.json`, { as: null }), 401, 'anonymous');
a.expect(await a.call('GET', `/issue_statuses/${id}.json`), 404, 'show is extended only');
await a.show('refused', 'Refusals: blank and duplicate name (422 with errors), unknown id (404), non-admins (403), anonymous (401), core path without show (404)');

a.expect(await a.call('DELETE', `/extended_api/issue_statuses/${id}.json`), 204);
a.expect(await a.call('GET', `/extended_api/issue_statuses/${id}.json`), 404, 'deleted');
// a status in use cannot go: status 1 (New) is used by the seeded issues
const inUse = a.expect(await a.call('DELETE', '/extended_api/issue_statuses/1.json'), 422, 'status in use');
await a.show('delete', 'Delete answers 204 and the status is gone; a status still used by issues is refused (422) with the reason');
a.check(/used by some issues/.test(inUse.json?.errors?.[0] || ''), `delete in use: the reason is not in the answer: ${inUse.text}`);

await t.done();
