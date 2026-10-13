// Enumerations through /extended_api: index by type, show, create, update,
// delete with reassignment, admin only for writes.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('enumerations');
const { client, setApiSettings } = api;
const a = client(t);
const name = `E2E activity ${Date.now() % 1000000}`;

await setApiSettings(t, { rest: true });

const all = a.expect(await a.call('GET', '/extended_api/enumerations.json'), 200);
a.check((all.json?.enumerations || []).some(e => e.type === 'issue_priorities'), 'index: no issue priorities');
const prios = a.expect(await a.call('GET', '/extended_api/enumerations/issue_priorities.json', { as: 'reporter' }), 200, 'index by type is public to API users, as in core');
a.expect(await a.call('GET', '/enumerations/issue_priorities.json', { as: 'reporter' }), 200);
const created = a.expect(await a.call('POST', '/extended_api/enumerations.json', {
  data: { enumeration: { type: 'TimeEntryActivity', name, active: true } },
}), 201);
const id = created.json?.enumeration?.id;
const updated = a.expect(await a.call('PUT', `/extended_api/enumerations/${id}.json`, { data: { enumeration: { name: `${name} v2`, active: false } } }), 200);
a.check(updated.json?.enumeration?.active === false, 'update: active not saved');
a.expect(await a.call('GET', `/extended_api/enumerations/${id}.xml`), 200);
await a.show('admin-crud', 'Index of all enumerations and by type (also for a non-admin, as in core), admin creates and updates a time entry activity');
a.check(!!prios.json, 'index by type: no JSON');

await t.go('/enumerations');
a.check(await t.page.locator('td', { hasText: `${name} v2` }).count() > 0, 'activity not in Administration > Enumerations');
await t.shot('admin-list', 'Administration > Enumerations shows the activity created and deactivated through the API');

a.expect(await a.call('POST', '/extended_api/enumerations.json', { data: { enumeration: { type: 'TimeEntryActivity', name: '' } } }), 422, 'blank name');
a.expect(await a.call('POST', '/extended_api/enumerations.json', { as: 'manager', data: { enumeration: { type: 'TimeEntryActivity', name: 'by manager' } } }), 403, 'not admin');
a.expect(await a.call('DELETE', `/extended_api/enumerations/${id}.json`, { as: 'reporter' }), 403, 'not admin');
a.expect(await a.call('GET', '/extended_api/enumerations/999999.json'), 404, 'unknown id');
// the Normal priority is used by the seeded issues: refused without reassign_to_id
const normal = (prios.json?.enumerations || []).find(e => e.name === 'Normal');
const inUse = a.expect(await a.call('DELETE', `/extended_api/enumerations/${normal?.id}.json`), 422, 'priority in use');
a.check(/Normal/.test(inUse.json?.errors?.[0] || ''), `delete in use: no reason in ${inUse.text}`);
await a.show('refused', 'Refusals: blank name (422), non-admins (403), unknown id (404), a priority in use without reassign_to_id (422 with the count)');

// in use, reassigned: log time on the new activity, then delete it onto Design
const activities = a.expect(await a.call('GET', '/extended_api/enumerations/time_entry_activities.json'), 200).json?.enumerations || [];
const other = activities.find(e => e.id !== id && e.active);
a.expect(await a.call('PUT', `/extended_api/enumerations/${id}.json`, { data: { enumeration: { active: true } } }), 200);
const te = a.expect(await a.call('POST', '/extended_api/time_entries.json', { data: { time_entry: { issue_id: 1, hours: 1, activity_id: id, comments: 'E2E reassign' } } }), 201);
a.expect(await a.call('DELETE', `/extended_api/enumerations/${id}.json`), 422, 'in use, no reassign');
a.expect(await a.call('DELETE', `/extended_api/enumerations/${id}.json?reassign_to_id=${other?.id}`), 204);
const moved = a.expect(await a.call('GET', `/extended_api/time_entries/${te.json?.time_entry?.id}.json`), 200);
a.check(moved.json?.time_entry?.activity?.id === other?.id, `reassign: time entry activity is ${JSON.stringify(moved.json?.time_entry?.activity)}`);
await a.show('reassign', 'An activity in use is refused, then deleted with reassign_to_id (204): its time entry moves to the other activity');

await t.done();
