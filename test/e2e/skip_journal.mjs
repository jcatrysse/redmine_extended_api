// skip_journal through /extended_api (decision 37 of the Jira migration): an admin's
// post-processing (description rewrite, parent set, relations, comment rewrite) leaves no
// journal and no edit trace; the same calls without the flag leave today's journals; a
// non-admin sending the flag is refused (403); notes together with the flag are refused (422).
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('skip-journal');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;
const OLD = '2021-03-03T10:00:00Z';

await setApiSettings(t, { rest: true });
const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const uid = login => users.find(u => u.login === login)?.id;
// imported issues, all dated 2021 (as an import creates them)
const mk = subject => a.call('POST', '/extended_api/issues.json?notify=false', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject, author_id: uid('reporter'), created_on: OLD, updated_on: OLD } },
});
const parent = a.expect(await mk(`E2E skip parent ${stamp}`), 201).json?.issue;
const child = a.expect(await mk(`E2E skip child ${stamp}`), 201).json?.issue;
const other = a.expect(await mk(`E2E skip related ${stamp}`), 201).json?.issue;
const spare = a.expect(await mk(`E2E skip spare ${stamp}`), 201).json?.issue;
// the imported comment on the child, by reporter in 2021
const note = a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?notify=false`, {
  data: { issue: { notes: `Imported comment, see #${stamp}`, updated_on: OLD }, journal: { user_id: uid('reporter'), updated_by_id: uid('reporter'), created_on: OLD, updated_on: OLD } },
}), 200).json?.journal;

// the second pass, with the flag
a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?notify=false`, {
  data: { issue: { description: `Relinked description, see #${other?.id}`, parent_issue_id: parent?.id }, skip_journal: true },
}), 204, 'description and parent with skip_journal');
const rel = a.expect(await a.call('POST', `/extended_api/issues/${child?.id}/relations.json?notify=false&skip_journal=1`, {
  data: { relation: { issue_to_id: other?.id, relation_type: 'relates' } },
}), 201).json?.relation;
const tmp = a.expect(await a.call('POST', `/extended_api/issues/${child?.id}/relations.json?notify=false&skip_journal=1`, {
  data: { relation: { issue_to_id: spare?.id, relation_type: 'blocks' } },
}), 201).json?.relation;
a.expect(await a.call('DELETE', `/extended_api/relations/${tmp?.id}.json?notify=false&skip_journal=1`), 204, 'relation delete with skip_journal');
a.expect(await a.call('PUT', `/extended_api/journals/${note?.id}.json?notify=false&skip_journal=1`, {
  data: { journal: { notes: `Imported comment, see #${other?.id}` } },
}), 204, 'comment rewrite with skip_journal');

const read = async id => a.expect(await a.call('GET', `/extended_api/issues/${id}.json?include=journals,relations`), 200).json?.issue;
const [p, c, o, sp] = [await read(parent?.id), await read(child?.id), await read(other?.id), await read(spare?.id)];
a.check(p?.journals?.length === 0 && o?.journals?.length === 0 && sp?.journals?.length === 0, `journals on parent ${p?.journals?.length}, related ${o?.journals?.length}, spare ${sp?.journals?.length}`);
a.check(c?.journals?.length === 1, `child journals: ${JSON.stringify(c?.journals)}`);
const j = c?.journals?.[0];
a.check(j?.notes === `Imported comment, see #${other?.id}` && j?.updated_on === OLD && j?.updated_by?.id === uid('reporter'),
  `rewritten comment: ${JSON.stringify(j)}`);
a.check([p, c, o, sp].every(x => x?.updated_on === OLD), `updated_on: ${[p, c, o, sp].map(x => x?.updated_on)}`);
a.check(c?.parent?.id === parent?.id && c?.description?.includes(`#${other?.id}`) && c?.relations?.length === 1,
  `child: parent ${c?.parent?.id}, relations ${JSON.stringify(c?.relations)}`);
await a.show('admin', 'Admin with skip_journal: description and parent set (204), a relation added, another added and removed, the comment rewritten (204); read back: no journal on parent, child or related issue except the imported comment, which keeps updated_on 2021 and updated_by Reporter; every updated_on still 2021');

await t.go(`/issues/${child?.id}`);
a.check(await t.page.locator('#history .journal').count() === 1, 'child page: more than the imported comment in the history');
await t.shot('child-page', 'The child: parent, new description and relation shown; the history has only the imported comment by Reporter E2E, not marked edited; updated 2021');
await t.go(`/issues/${parent?.id}`);
a.check(await t.page.locator('#history .journal').count() === 0, 'parent page: a journal in the history ("Subtask added")');
await t.shot('parent-page', 'The parent: the subtask is listed, no "Subtask added" in the history, updated 2021');

// the same pass without the flag: today's journals
const parent2 = a.expect(await mk(`E2E journal parent ${stamp}`), 201).json?.issue;
const child2 = a.expect(await mk(`E2E journal child ${stamp}`), 201).json?.issue;
a.expect(await a.call('PUT', `/extended_api/issues/${child2?.id}.json?notify=false`, {
  data: { issue: { description: 'Relinked description', parent_issue_id: parent2?.id } },
}), 200, 'without skip_journal the answer is the journal');
a.expect(await a.call('POST', `/extended_api/issues/${child2?.id}/relations.json?notify=false`, {
  data: { relation: { issue_to_id: other?.id, relation_type: 'relates' } },
}), 201);
const [p2, c2] = [await read(parent2?.id), await read(child2?.id)];
a.check(p2?.journals?.length === 1 && c2?.journals?.length === 2, `without the flag: parent ${p2?.journals?.length}, child ${c2?.journals?.length} journals`);
a.check(c2?.updated_on !== OLD, 'without the flag: child updated_on unchanged');
await a.show('without-flag', 'The same pass without skip_journal: the update answers with its journal, the parent gets "Subtask added", the relation a journal on both issues, updated_on moves to now');
await t.go(`/issues/${child2?.id}`);
await t.shot('without-flag-page', 'Without the flag the child shows the update and the relation in its history, updated a moment ago');

// refusals
a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?skip_journal=1`, { as: 'manager', data: { issue: { description: 'by manager' } } }), 403, 'manager is no admin');
a.expect(await a.call('POST', `/extended_api/issues/${child?.id}/relations.json?skip_journal=1`, { as: 'manager', data: { relation: { issue_to_id: parent?.id, relation_type: 'relates' } } }), 403, 'manager is no admin');
a.expect(await a.call('PUT', `/extended_api/journals/${note?.id}.json?skip_journal=1`, { as: 'manager', data: { journal: { notes: 'by manager' } } }), 403, 'manager is no admin');
a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?skip_journal=1`, { as: 'reporter', data: { issue: { description: 'by reporter' } } }), 403, 'reporter');
a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?skip_journal=1`, { data: { issue: { notes: 'a comment' } } }), 422, 'notes need a journal');
a.expect(await a.call('PUT', `/extended_api/issues/${child?.id}.json?skip_journal=0`, { as: 'manager', data: { issue: { description: `Manager edit ${stamp}` } } }), 200, 'skip_journal=0 is today\'s update');
const after = await read(child?.id);
a.check(after?.description === `Manager edit ${stamp}` && after?.journals?.length === 2 && !after?.journals?.some(x => /by (manager|reporter)/.test(x.notes || '')),
  `after the refusals: ${after?.description}, ${after?.journals?.length} journals`);
await a.show('refused', 'Manager and reporter with skip_journal: 403 on issue, relation and comment, nothing changed; admin with notes and skip_journal: 422 "Notes is invalid"; skip_journal=0 as manager: a normal update with its journal');

await t.login('manager');
await t.go(`/issues/${child?.id}`);
await t.shot('member-page', 'The child seen by the manager after the refusals: only the imported comment and the manager\'s own edit (skip_journal=0) in the history');

await t.done();
