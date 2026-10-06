// Custom fields through /extended_api: show, create (list and enumeration
// formats), update (enumeration options keep their ids), delete, admin only.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('custom-fields');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

await setApiSettings(t, { rest: true });

const list = a.expect(await a.call('POST', '/extended_api/custom_fields.json', {
  data: { type: 'IssueCustomField', custom_field: { name: `E2E region ${stamp}`, field_format: 'list', possible_values: ['EU', 'US', 'APAC'], is_for_all: true, tracker_ids: [1], visible: true } },
}), 201);
const listId = list.json?.custom_field?.id;
a.check(JSON.stringify(list.json?.custom_field?.possible_values?.map(v => v.value ?? v)) === JSON.stringify(['EU', 'US', 'APAC']), `create list: possible_values ${JSON.stringify(list.json?.custom_field?.possible_values)}`);
const enumCf = a.expect(await a.call('POST', '/extended_api/custom_fields.json', {
  data: { type: 'IssueCustomField', custom_field: { name: `E2E cause ${stamp}`, field_format: 'enumeration', is_for_all: true, tracker_ids: [1], enumerations: [{ name: 'Configuration' }, { name: 'Code' }, { name: 'Third-party' }] } },
}), 201);
const enumId = enumCf.json?.custom_field?.id;
const options = enumCf.json?.custom_field?.enumerations || [];
a.check(options.length === 3, `create enumeration: ${options.length} options`);
await a.show('admin-create', 'Admin creates a list custom field and an enumeration custom field with three options (201)');

const code = options.find(o => o.name === 'Code');
const third = options.find(o => o.name === 'Third-party');
const renamed = a.expect(await a.call('PATCH', `/extended_api/custom_fields/${enumId}.json`, {
  data: { custom_field: { enumerations: [{ id: code?.id, name: 'Code', active: true }, { id: third?.id, name: 'Third-party vendor', active: false }], default_value: String(code?.id) } },
}), 200);
const after = renamed.json?.custom_field?.enumerations || [];
a.check(after.find(o => o.id === third?.id)?.name === 'Third-party vendor', `update: option ${third?.id} not renamed in place: ${JSON.stringify(after)}`);
a.check(String(renamed.json?.custom_field?.default_value) === String(code?.id), `update: default_value ${renamed.json?.custom_field?.default_value}`);
a.expect(await a.call('GET', `/extended_api/custom_fields/${listId}.xml`), 200);
await a.show('admin-update', 'Admin renames and deactivates an option of the enumeration field keeping its id, sets the default (200); show as XML');

await t.go('/custom_fields?tab=IssueCustomField');
await t.shot('admin-list', 'Administration > Custom fields lists both fields made through the API');
await t.go(`/custom_fields/${enumId}/edit`);
await t.shot('admin-edit', 'The enumeration field in the admin form: the options and the default set through the API');
await t.login('manager');
await t.go('/projects/e2e-project/issues/new?issue[tracker_id]=1');
a.check(await t.page.locator('label', { hasText: `E2E region ${stamp}` }).count() > 0, 'the list field is not on the new issue form');
await t.shot('issue-form', 'Both fields are on the new issue form of e2e-project for a member (Bug tracker)');

a.expect(await a.call('POST', '/extended_api/custom_fields.json', { data: { type: 'IssueCustomField', custom_field: { name: '', field_format: 'string' } } }), 422, 'blank name');
const noType = a.expect(await a.call('POST', '/extended_api/custom_fields.json', { data: { custom_field: { name: 'no type', field_format: 'string' } } }), 422, 'no type');
a.check(noType.json?.errors?.[0] === 'Type is invalid', `no type: ${noType.text.slice(0, 100)}`);
a.expect(await a.call('POST', '/extended_api/custom_fields.json', { as: 'manager', data: { type: 'IssueCustomField', custom_field: { name: 'by manager', field_format: 'string' } } }), 403, 'not admin');
a.expect(await a.call('GET', `/extended_api/custom_fields/${listId}.json`, { as: 'reporter' }), 403, 'not admin');
a.expect(await a.call('GET', '/extended_api/custom_fields/999999.json'), 404, 'unknown id');
a.expect(await a.call('GET', `/custom_fields/${listId}.json`), 404, 'show is extended only');
await a.show('refused', 'Refusals: blank name (422), no type (422 Type is invalid, no HTML page), non-admins (403), unknown id (404), core path without show (404)');

a.expect(await a.call('DELETE', `/extended_api/custom_fields/${listId}.json`), 204);
a.expect(await a.call('DELETE', `/extended_api/custom_fields/${enumId}.json`), 204);
a.expect(await a.call('GET', `/extended_api/custom_fields/${listId}.json`), 404, 'deleted');
await a.show('delete', 'Both fields are deleted (204) and gone (404)');

await t.done();
