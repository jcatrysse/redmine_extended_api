// POST /extended_api/issues/:id/history.json (decision 41 of the Jira migration): imported
// status, assignee and priority changes become journals with their own user and time, around an
// imported comment; the issue keeps updated_on, closed_on and its watchers; an uploaded file is
// attached with its own author and time. With redmine_agile installed, its cumulative flow for the
// issue before and after. Refusals: non-admin 403, invalid input 422, core path 404.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('issue-history');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

await setApiSettings(t, { rest: true });
const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const uid = login => users.find(u => u.login === login)?.id;
const statuses = a.expect(await a.call('GET', '/extended_api/issue_statuses.json'), 200).json?.issue_statuses || [];
const sid = name => statuses.find(s => s.name === name)?.id;
const priorities = a.expect(await a.call('GET', '/extended_api/enumerations/issue_priorities.json'), 200).json?.enumerations || [];
const pid = name => priorities.find(p => p.name === name)?.id;
const [NEW, PROGRESS, RESOLVED, CLOSED] = ['New', 'In Progress', 'Resolved', 'Closed'].map(sid);

// the imported issue as the first pass leaves it: current status Closed, dates from Jira
const issue = a.expect(await a.call('POST', '/extended_api/issues.json?notify=false', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E history ${stamp}`, status_id: CLOSED,
    priority_id: pid('High'), assigned_to_id: uid('manager'), author_id: uid('reporter'),
    created_on: '2024-03-01T09:00:00Z', updated_on: '2024-03-20T16:00:00Z', closed_on: '2024-03-15T12:00:00Z' } },
}), 201).json?.issue;
// a new issue starts in the tracker's default status (workflow): the import closes it without a journal
a.expect(await a.call('PUT', `/extended_api/issues/${issue?.id}.json?notify=false&skip_journal=1`, {
  data: { issue: { status_id: CLOSED, updated_on: '2024-03-20T16:00:00Z', closed_on: '2024-03-15T12:00:00Z' } },
}), 204);
a.expect(await a.call('PUT', `/extended_api/issues/${issue?.id}.json?notify=false`, {
  data: { issue: { notes: `Imported comment ${stamp}`, updated_on: '2024-03-20T16:00:00Z' },
    journal: { user_id: uid('reporter'), created_on: '2024-03-05T10:00:00Z', updated_on: '2024-03-05T10:00:00Z' } },
}), 200);
const read = async () => a.expect(await a.call('GET', `/extended_api/issues/${issue?.id}.json?include=journals,watchers,attachments`), 200).json?.issue;
const before = await read();

const chart = `/projects/e2e-project/agile/charts?set_filter=1&f[]=status_id&op[status_id]=*&f[]=issue_id&op[issue_id]==&v[issue_id][]=${issue?.id}` +
  '&f[]=chart_period&op[chart_period]=><&v[chart_period][]=2024-03-01&v[chart_period][]=2024-03-21&chart=cumulative_flow&interval_size=day';
// redmine_agile is optional: without it the chart steps are skipped, the rest is checked
async function cumulativeFlow(name, caption) {
  if (!agile) return null;
  const res = t.page.waitForResponse(r => r.url().includes('/agile/charts/render_chart'), { timeout: 20000 }).catch(() => null);
  await t.go(chart);
  const r = await res;
  const data = r && r.status() === 200 ? await r.json() : null;
  await t.page.waitForTimeout(1000);
  await t.shot(name, caption);
  // status name per day: the dataset with a 1 on that day
  return (data?.labels || []).map((_, i) => (data.datasets.find(d => Number(d.data[i]) === 1) || {}).label);
}

await t.login('admin');
const agile = (await t.page.request.get(`${t.BASE}/projects/e2e-project/agile/charts`)).status() === 200;
await t.go(`/issues/${issue?.id}`);
await t.shot('before-page', 'Before: the imported issue (Closed) shows only the imported comment of 2024-03-05; updated 2024-03-20');
const flowBefore = await cumulativeFlow('before-cumulative-flow', 'Before: redmine_agile\'s cumulative flow of the issue, 2024-03-01..21: Closed every day (no status history)');
// the first point is the day before the period (the issue does not exist yet)
if (flowBefore) a.check(flowBefore.length > 1 && flowBefore.slice(1).every(s => s === 'Closed'), `cumulative flow before: ${flowBefore}`);

// upload the Jira history file, then write the history
const up = a.expect(await a.call('POST', '/extended_api/uploads.json?filename=upload.json', { body: `{"issue":${issue?.id}}`, contentType: 'application/octet-stream' }), 201).json?.upload;
const written = a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, {
  data: {
    journals: [
      { user_id: uid('manager'), created_on: '2024-03-02T08:00:00Z', details: [
        { property: 'attr', prop_key: 'status_id', old_value: String(NEW), value: String(PROGRESS) },
        { property: 'attr', prop_key: 'assigned_to_id', old_value: null, value: String(uid('manager')) }] },
      { user_id: uid('manager'), created_on: '2024-03-10T14:00:00Z', details: [
        { property: 'attr', prop_key: 'status_id', old_value: String(PROGRESS), value: String(RESOLVED) },
        { property: 'attr', prop_key: 'priority_id', old_value: String(pid('Normal')), value: String(pid('High')) }] },
      { user_id: uid('reporter'), created_on: '2024-03-15T12:00:00Z', details: [
        { property: 'attr', prop_key: 'status_id', old_value: String(RESOLVED), value: String(CLOSED) }] },
    ],
    attachments: [{ token: up?.token, filename: 'jira-history.json', content_type: 'application/json', description: 'Jira history',
      author_id: uid('reporter'), created_on: '2024-03-20T16:00:00Z' }],
  },
}), 201).json;
a.check(written?.journal_ids?.length === 3 && written?.attachment_ids?.length === 1, `answer: ${JSON.stringify(written)}`);

const after = await read();
a.check(after?.updated_on === before?.updated_on && after?.closed_on === before?.closed_on && after?.status?.id === CLOSED,
  `issue changed: updated_on ${before?.updated_on} -> ${after?.updated_on}, closed_on ${before?.closed_on} -> ${after?.closed_on}`);
a.check(JSON.stringify(after?.watchers) === JSON.stringify(before?.watchers), `watchers: ${JSON.stringify(before?.watchers)} -> ${JSON.stringify(after?.watchers)}`);
const order = (after?.journals || []).map(j => j.created_on);
a.check(JSON.stringify(order) === JSON.stringify(['2024-03-02T08:00:00Z', '2024-03-05T10:00:00Z', '2024-03-10T14:00:00Z', '2024-03-15T12:00:00Z']), `journal order: ${order}`);
a.check((after?.journals || []).every(j => !j.updated_by), 'a history journal is marked edited');
const file = (after?.attachments || []).find(f => f.filename === 'jira-history.json');
a.check(file?.author?.id === uid('reporter') && file?.created_on === '2024-03-20T16:00:00Z', `attachment: ${JSON.stringify(file)}`);
await a.show('admin', 'Admin writes three history journals (manager 2024-03-02 and 03-10, reporter 03-15) and attaches jira-history.json (reporter, 2024-03-20): 201 with the ids; read back: journals in time order around the comment, updated_on, closed_on, watchers unchanged');

await t.go(`/issues/${issue?.id}`);
await t.shot('after-page', 'After: the history shows the status, assignee and priority changes at their own time, by their own user, around the imported comment; still "Updated" 2024-03-20, jira-history.json by Reporter E2E');
const flowAfter = await cumulativeFlow('after-cumulative-flow', 'After: the cumulative flow follows the imported history: New on 03-01, In Progress from 03-02, Resolved from 03-10, Closed from 03-15');
const at = day => flowAfter[day]; // point 0 is the day before 2024-03-01
if (flowAfter) a.check(at(1) === 'New' && at(2) === 'In Progress' && at(9) === 'In Progress' && at(10) === 'Resolved' && at(15) === 'Closed' && at(21) === 'Closed',
  `cumulative flow after: ${flowAfter}`);

// refusals
const one = [{ user_id: uid('manager'), created_on: '2024-03-02T08:00:00Z', details: [{ property: 'attr', prop_key: 'status_id', old_value: String(NEW), value: String(PROGRESS) }] }];
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, { as: 'manager', data: { journals: one } }), 403, 'manager is no admin');
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, { as: 'reporter', data: { journals: one } }), 403, 'reporter');
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, { as: null, data: { journals: one } }), 401, 'anonymous');
a.expect(await a.call('POST', `/issues/${issue?.id}/history.json`, { data: { journals: one } }), 404, 'core path');
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, { data: { journals: [] } }), 422, 'empty');
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, {
  data: { journals: [{ ...one[0], details: [{ property: 'attr', prop_key: 'subject', old_value: 'a', value: 'b' }] }] } }), 422, 'other key');
a.expect(await a.call('POST', `/extended_api/issues/${issue?.id}/history.json`, {
  data: { journals: [{ ...one[0], user_id: 999999, created_on: 'soon', notes: 'a comment', details: [{ property: 'attr', prop_key: 'status_id', old_value: '1', value: '999999' }] }] } }), 422, 'unknown user, bad time, notes, unknown status');
const final = await read();
a.check(final?.journals?.length === 4, `after the refusals: ${final?.journals?.length} journals`);
await a.show('refused', 'Manager and reporter: 403; anonymous: 401; core path: 404; admin with an empty list, another key, or an unknown user + unparseable time + notes + unknown status: 422 with every reason; nothing written');

await t.done();
