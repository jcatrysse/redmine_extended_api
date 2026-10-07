// Issue import overrides through /extended_api: an admin sets author_id,
// created_on, updated_on and closed_on on create and update; anybody else, or the
// core path, gets the normal values. The Redmine 7 webhooks see what is stored.
// This is the function that silently lost the overrides on Redmine 7 before the
// update_columns fix.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('issue-overrides');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

const receiver = await api.webhookReceiver();
const hookFor = receiver.hookFor;

await setApiSettings(t, { rest: true, webhooks: true });
await api.addWebhook(t, receiver.url);
await t.shot('webhook', 'A Redmine 7 webhook for issue created/updated in e2e-project, pointing at a receiver in the test');

const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const uid = login => users.find(u => u.login === login)?.id;
const statuses = a.expect(await a.call('GET', '/extended_api/issue_statuses.json'), 200).json?.issue_statuses || [];
const closed = statuses.find(s => s.is_closed);

// admin, extended path: the overrides are stored
// without notify=false: that would silence the webhooks too (see webhooks.mjs)
const imported = a.expect(await a.call('POST', '/extended_api/issues.json', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E imported ${stamp}`, author_id: uid('manager'),
    created_on: '2020-01-02T03:04:05Z', updated_on: '2020-01-03T03:04:05Z' } },
}), 201);
const id = imported.json?.issue?.id;
const stored = a.expect(await a.call('GET', `/extended_api/issues/${id}.json`), 200).json?.issue;
a.check(stored?.author?.id === uid('manager'), `admin create: author is ${JSON.stringify(stored?.author)}, expected manager`);
a.check(stored?.created_on === '2020-01-02T03:04:05Z', `admin create: created_on is ${stored?.created_on}`);
a.check(stored?.updated_on === '2020-01-03T03:04:05Z', `admin create: updated_on is ${stored?.updated_on}`);
await a.show('admin-create', 'Admin imports an issue with author manager and dates in 2020 (201); reading it back shows the stored author and dates');

const created = await hookFor('issue.created', id);
a.check(!!created, 'no issue.created webhook received');
a.check(created?.data?.issue?.author?.id === uid('manager') && created?.data?.issue?.created_on === '2020-01-02T03:04:05Z',
  `webhook issue.created: author ${JSON.stringify(created?.data?.issue?.author)}, created_on ${created?.data?.issue?.created_on}`);

await t.go(`/issues/${id}`);
a.check(await t.page.locator('.author', { hasText: 'Manager E2E' }).count() > 0, 'issue page: author is not Manager E2E');
await t.page.locator('.author a[title]').last().hover().catch(() => {});
await t.shot('admin-create-page', 'The imported issue: "Added by Manager E2E" years ago (created 2020-01-02), not by the admin who posted it');

// update with updated_on / closed_on
const closing = a.expect(await a.call('PUT', `/extended_api/issues/${id}.json`, {
  data: { issue: { status_id: closed?.id, notes: 'Closed by the import', updated_on: '2021-05-06T07:08:09Z', closed_on: '2021-05-06T07:08:00Z' } },
}), 200);
a.check(closing.json?.journal?.notes === 'Closed by the import', 'admin update: no journal payload in the answer');
const after = a.expect(await a.call('GET', `/extended_api/issues/${id}.json`), 200).json?.issue;
a.check(after?.status?.id === closed?.id && after?.closed_on === '2021-05-06T07:08:00Z' && after?.updated_on === '2021-05-06T07:08:09Z',
  `admin update: status ${after?.status?.id}, closed_on ${after?.closed_on}, updated_on ${after?.updated_on}`);
a.check(after?.created_on === '2020-01-02T03:04:05Z' && after?.author?.id === uid('manager'), 'admin update: the create overrides changed');
const updatedHook = await hookFor('issue.updated', id);
a.check(!!updatedHook, 'no issue.updated webhook received');
a.check(updatedHook?.data?.issue?.closed_on === '2021-05-06T07:08:00Z', `webhook issue.updated: closed_on ${updatedHook?.data?.issue?.closed_on}`);
await a.show('admin-update', 'Admin closes it with updated_on/closed_on in 2021 (200, journal returned); the stored dates are the given ones');
await t.go(`/issues/${id}`);
await t.shot('admin-update-page', 'The issue page after the import update: closed, the note in the history');

const createdHookShown = { ...created, data: { issue: { id: created?.data?.issue?.id, author: created?.data?.issue?.author, created_on: created?.data?.issue?.created_on } } };
const updatedHookShown = { type: updatedHook?.type, data: { issue: { id: updatedHook?.data?.issue?.id, closed_on: updatedHook?.data?.issue?.closed_on, updated_on: updatedHook?.data?.issue?.updated_on }, journal: { notes: updatedHook?.data?.journal?.notes } } };
await t.page.setContent(`<!doctype html><meta charset="utf-8"><body style="font:13px sans-serif;margin:16px">
  <h1 style="font-size:16px">Webhook payloads received by the test (shortened)</h1>
  <pre>${JSON.stringify([createdHookShown, updatedHookShown], null, 2).replace(/</g, '&lt;')}</pre></body>`);
await t.shot('webhook-payloads', 'The webhooks carry the imported author and dates, the same values as stored');

// not admin, core path, invalid input
const byManager = a.expect(await a.call('POST', '/extended_api/issues.json', {
  as: 'manager', data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E manager ${stamp}`, author_id: uid('reporter'), created_on: '2020-01-02T03:04:05Z' } },
}), 201);
const m = a.expect(await a.call('GET', `/extended_api/issues/${byManager.json?.issue?.id}.json`), 200).json?.issue;
a.check(m?.author?.id === uid('manager') && !m?.created_on?.startsWith('2020'), `manager create: author ${m?.author?.id}, created_on ${m?.created_on}`);
const byReporter = a.expect(await a.call('POST', '/extended_api/issues.json', {
  as: 'reporter', data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E reporter ${stamp}`, author_id: uid('manager'), created_on: '2020-01-02T03:04:05Z' } },
}), 201);
a.check(byReporter.json?.issue?.author?.id === uid('reporter') && !byReporter.json?.issue?.created_on?.startsWith('2020'), 'reporter create: overrides applied');
const core = a.expect(await a.call('POST', '/issues.json', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E core ${stamp}`, author_id: uid('manager'), created_on: '2020-01-02T03:04:05Z' } },
}), 201);
a.check(core.json?.issue?.author?.id === uid('admin') && !core.json?.issue?.created_on?.startsWith('2020'), 'core path: overrides applied');
await a.show('ignored', 'The overrides are ignored for manager and reporter (no admin) and on the core path /issues.json: author and dates are the real ones');

await t.login('manager');
await t.go(`/issues/${byManager.json?.issue?.id}`);
await t.shot('manager-page', 'Issue posted by manager with author_id=reporter and a 2020 date: added by Manager E2E, just now');

const priv = { project_id: 'e2e-private', tracker_id: 1, subject: 'outsider' };
const c = await a.call('POST', '/issues.json', { as: 'outsider', data: { issue: priv } });
const x = await a.call('POST', '/extended_api/issues.json', { as: 'outsider', data: { issue: priv } });
a.check(c.status >= 400 && x.status === c.status, `outsider in the private project: core ${c.status}, extended ${x.status}`);
const bad = a.expect(await a.call('POST', '/extended_api/issues.json', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E bad date ${stamp}`, author_id: 999999, created_on: 'not a date' } },
}), 422, 'invalid created_on and unknown author');
a.check(JSON.stringify(bad.json?.errors) === JSON.stringify(['Author is invalid', 'Created is invalid']), `invalid overrides: ${bad.text}`);
const badJournal = a.expect(await a.call('PUT', `/extended_api/issues/${id}.json`, {
  data: { issue: { notes: 'never saved' }, journal: { created_on: '2021-13-45' } },
}), 422, 'invalid journal created_on');
a.check(badJournal.json?.errors?.[0] === 'Created is invalid', `invalid journal override: ${badJournal.text}`);
a.expect(await a.call('POST', '/extended_api/issues.json', { data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: '' } } }), 422, 'blank subject');
a.expect(await a.call('PUT', '/extended_api/issues/999999.json', { data: { issue: { updated_on: '2021-01-01T00:00:00Z' } } }), 404, 'unknown issue');
await a.show('refused', 'Outsider in the private project is refused as on the core path; an unparseable date or unknown author is refused (422, nothing saved); blank subject 422; unknown issue 404');

receiver.close();
await t.done();
