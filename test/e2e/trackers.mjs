// Trackers through /extended_api: show, create (with copy_workflow_from), update,
// delete, admin only, and the refusals.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('trackers');
const { client, setApiSettings } = api;
const a = client(t);
const name = `E2E tracker ${Date.now() % 1000000}`;

await setApiSettings(t, { rest: true });

const created = a.expect(await a.call('POST', '/extended_api/trackers.json', {
  data: { tracker: { name, default_status_id: 1, core_fields: ['assigned_to_id', 'due_date'], project_ids: [1] }, copy_workflow_from: 1 },
}), 201);
const id = created.json?.tracker?.id;
a.check(JSON.stringify(created.json?.tracker?.core_fields) === JSON.stringify(['assigned_to_id', 'due_date']), `create: core_fields ${JSON.stringify(created.json?.tracker?.core_fields)}`);
a.check(created.json?.tracker?.projects?.some(p => p.identifier === 'e2e-project'), 'create: project not linked');
const updated = a.expect(await a.call('PATCH', `/extended_api/trackers/${id}.json`, {
  data: { tracker: { core_fields: ['assigned_to_id', 'due_date', 'category_id'], is_in_roadmap: false } },
}), 200);
a.check(updated.json?.tracker?.core_fields?.includes('category_id'), 'update: core_fields not saved');
a.expect(await a.call('GET', `/extended_api/trackers/${id}.xml`), 200);
await a.show('admin-crud', 'Admin creates a tracker linked to e2e-project with workflow copied from Bug (201), updates its fields (200), shows it as XML');

await t.go('/trackers');
a.check(await t.page.locator('table.list td', { hasText: name }).count() > 0, 'tracker not in Administration > Trackers');
await t.shot('admin-list', 'Administration > Trackers lists the tracker created through the API');
await t.go(`/trackers/${id}/edit`);
await t.shot('admin-edit', 'Its edit form: the standard fields and the project set through the API');
await t.login('manager');
await t.go('/projects/e2e-project/issues/new');
a.check(await t.page.locator('#issue_tracker_id option', { hasText: name }).count() > 0, 'the new tracker is not offered in e2e-project');
await t.page.selectOption('#issue_tracker_id', { label: name });
await t.page.waitForResponse(r => r.url().includes('/issues/new.js') || r.url().includes('/form'), { timeout: 10000 }).catch(() => {});
await t.settle();
t.check('pick the new tracker');
await t.shot('in-project', 'A member of e2e-project picks the new tracker: the form shows only the standard fields set through the API (assignee, due date)');

a.expect(await a.call('POST', '/extended_api/trackers.json', { data: { tracker: { name: '' } } }), 422, 'blank name');
a.expect(await a.call('POST', '/extended_api/trackers.json', { data: { tracker: { name } } }), 422, 'duplicate name');
a.expect(await a.call('GET', '/extended_api/trackers/999999.json'), 404, 'unknown id');
a.expect(await a.call('POST', '/extended_api/trackers.json', { as: 'manager', data: { tracker: { name: 'by manager', default_status_id: 1 } } }), 403, 'not admin');
a.expect(await a.call('DELETE', `/extended_api/trackers/${id}.json`, { as: 'reporter' }), 403, 'not admin');
a.expect(await a.call('GET', `/trackers/${id}.json`), 404, 'show is extended only');
const inUse = a.expect(await a.call('DELETE', '/extended_api/trackers/1.json'), 422, 'tracker in use');
a.check(/E2E project/.test(inUse.json?.errors?.[0] || ''), `delete in use: no reason in ${inUse.text}`);
await a.show('refused', 'Refusals: blank and duplicate name (422), unknown id (404), non-admins (403), core path without show (404), tracker in use (422 naming the projects)');

a.expect(await a.call('DELETE', `/extended_api/trackers/${id}.json`), 204);
a.expect(await a.call('GET', `/extended_api/trackers/${id}.json`), 404, 'deleted');
await a.show('delete', 'An unused tracker is deleted (204) and gone (404)');

await t.done();
