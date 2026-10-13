// Issue relations through /extended_api: create and delete with the core
// permissions (manage_issue_relations), notify=false accepted, refusals as in core.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('relations');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

await setApiSettings(t, { rest: true });
const mk = subject => a.call('POST', '/extended_api/issues.json?notify=false', { data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject } } });
const one = a.expect(await mk(`E2E rel one ${stamp}`), 201).json?.issue;
const two = a.expect(await mk(`E2E rel two ${stamp}`), 201).json?.issue;

const rel = a.expect(await a.call('POST', `/extended_api/issues/${one?.id}/relations.json?notify=false`, {
  as: 'manager', data: { relation: { issue_to_id: two?.id, relation_type: 'blocks' } },
}), 201);
a.expect(await a.call('GET', `/extended_api/relations/${rel.json?.relation?.id}.json`, { as: 'manager' }), 200);
await a.show('create', 'Manager (manage_issue_relations) relates two issues with notify=false (201) and reads the relation back');

await t.login('manager');
await t.go(`/issues/${one?.id}`);
a.check(await t.page.locator('#relations', { hasText: `E2E rel two ${stamp}` }).count() > 0, 'relation not on the issue page');
await t.shot('issue-page', 'The issue page shows "Blocks" the other issue');

a.expect(await a.call('POST', `/extended_api/issues/${one?.id}/relations.json`, { as: 'reporter', data: { relation: { issue_to_id: two?.id, relation_type: 'relates' } } }), 403, 'reporter has no manage_issue_relations');
a.expect(await a.call('POST', `/extended_api/issues/${one?.id}/relations.json`, { as: 'manager', data: { relation: { issue_to_id: two?.id, relation_type: 'blocks' } } }), 422, 'duplicate');
a.expect(await a.call('POST', `/extended_api/issues/${one?.id}/relations.json`, { as: 'manager', data: { relation: { issue_to_id: 999999, relation_type: 'relates' } } }), 422, 'unknown target');
a.expect(await a.call('POST', `/extended_api/issues/${one?.id}/relations.json`, { as: 'manager', data: { relation: { issue_to_id: one?.id, relation_type: 'relates' } } }), 422, 'to itself');
a.expect(await a.call('DELETE', `/extended_api/relations/${rel.json?.relation?.id}.json`, { as: 'reporter' }), 403, 'reporter');
a.expect(await a.call('DELETE', `/extended_api/relations/${rel.json?.relation?.id}.json`, { as: 'outsider' }), 403, 'outsider');
await a.show('refused', 'Refusals as in core: reporter without manage_issue_relations and outsider (403), duplicate, unknown target, relation to itself (422)');

a.expect(await a.call('DELETE', `/extended_api/relations/${rel.json?.relation?.id}.json?notify=false`, { as: 'manager' }), 204);
a.expect(await a.call('GET', `/extended_api/relations/${rel.json?.relation?.id}.json`, { as: 'manager' }), 404, 'deleted');
await a.show('delete', 'Manager deletes the relation with notify=false (204); it is gone (404)');
await t.go(`/issues/${one?.id}`);
await t.shot('issue-page-after', 'The issue page after the delete: no related issues left, the history shows add and delete of the relation');

await t.done();
