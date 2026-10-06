// Roles through /extended_api: create (permissions, copy_workflow_from), update,
// delete, admin only; show and index stay the core ones.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('roles');
const { client, setApiSettings } = api;
const a = client(t);
const name = `E2E role ${Date.now() % 1000000}`;

await setApiSettings(t, { rest: true });

const created = a.expect(await a.call('POST', '/extended_api/roles.json', {
  data: { role: { name, assignable: true, permissions: ['view_issues', 'add_issues'], issues_visibility: 'own' }, copy_workflow_from: 5 },
}), 201);
const id = created.json?.role?.id;
a.check(created.mode === 'extended', `create: x-redmine-extended-api is "${created.mode}"`);
const updated = a.expect(await a.call('PUT', `/extended_api/roles/${id}.json`, {
  data: { role: { permissions: ['view_issues', 'add_issues', 'edit_issues'] } },
}), 200);
a.check(updated.json?.role?.permissions?.includes('edit_issues'), `update: permissions ${JSON.stringify(updated.json?.role?.permissions)}`);
const shown = a.expect(await a.call('GET', `/extended_api/roles/${id}.json`), 200);
a.check(shown.json?.role?.issues_visibility === 'own', 'show: issues_visibility not saved');
await a.show('admin-crud', 'Admin creates a role with permissions and the Reporter workflow (201), adds edit_issues (200); show is the core one, proxied');

await t.go(`/roles/${id}/edit`);
a.check(await t.page.locator('#role_permissions_edit_issues').isChecked(), 'edit_issues not checked in the role form');
await t.shot('admin-edit', 'Administration > Roles: the role made through the API, with View/Add/Edit issues ticked');

a.expect(await a.call('POST', '/extended_api/roles.json', { data: { role: { name: '' } } }), 422, 'blank name');
a.expect(await a.call('POST', '/extended_api/roles.json', { data: { role: { name } } }), 422, 'duplicate name');
a.expect(await a.call('POST', '/extended_api/roles.json', { as: 'manager', data: { role: { name: 'by manager' } } }), 403, 'not admin');
a.expect(await a.call('PUT', `/extended_api/roles/${id}.json`, { as: 'outsider', data: { role: { name: 'by outsider' } } }), 403, 'not admin');
a.expect(await a.call('DELETE', `/extended_api/roles/${id}.json`, { as: null }), 401, 'anonymous');
a.expect(await a.call('PUT', '/extended_api/roles/999999.json', { data: { role: { name: 'x' } } }), 404, 'unknown id');
const inUse = a.expect(await a.call('DELETE', '/extended_api/roles/5.json'), 422, 'role in use');
a.check((inUse.json?.errors?.[0] || '').length > 0, `delete in use: no reason in ${inUse.text}`);
await a.show('refused', 'Refusals: blank and duplicate name (422), non-admins (403), anonymous (401), unknown id (404), the Reporter role in use (422 with the reason)');

a.expect(await a.call('DELETE', `/extended_api/roles/${id}.json`), 204);
a.expect(await a.call('GET', `/extended_api/roles/${id}.json`), 404, 'deleted');
await a.show('delete', 'An unused role is deleted (204) and gone (404)');

await t.done();
