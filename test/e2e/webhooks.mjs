// notify=false silences Redmine 7 webhooks too (decision of Jan, 2026-10-07):
// an /extended_api issue create or update with notify=false or send_notification=0
// sends no webhook, for any user; without it, or on the core path, webhooks are sent.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('webhooks');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;
const receiver = await api.webhookReceiver();
const results = [];

await setApiSettings(t, { rest: true, webhooks: true });
await api.addWebhook(t, receiver.url);
await t.go('/webhooks');
await t.shot('webhook', 'A Redmine 7 webhook for issue created/updated in e2e-project, pointing at a receiver in the test');

// one issue per user and path; expected webhooks per issue
async function create(as, path, label, expected) {
  const res = a.expect(await a.call('POST', path, {
    as, data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E hook ${label} ${stamp}` } },
  }), 201, label);
  results.push({ label, as, path, id: res.json?.issue?.id, expected });
  return res.json?.issue?.id;
}

const quietAdmin = await create('admin', '/extended_api/issues.json?notify=false', 'admin quiet', []);
const loudAdmin = await create('admin', '/extended_api/issues.json', 'admin loud', ['issue.created', 'issue.updated']);
await create('manager', '/extended_api/issues.json?notify=false', 'manager quiet', []);
await create('manager', '/extended_api/issues.json', 'manager loud', ['issue.created']);
await create('reporter', '/extended_api/issues.json?send_notification=0', 'reporter quiet', []);
await create('reporter', '/issues.json?notify=false', 'reporter core path', ['issue.created']);

// updates of the admin issues: the quiet one stays quiet, the loud one gets one update hook
a.expect(await a.call('PUT', `/extended_api/issues/${quietAdmin}.json?notify=false`, { data: { issue: { notes: 'quiet note' } } }), 200);
a.expect(await a.call('PUT', `/extended_api/issues/${loudAdmin}.json`, { data: { issue: { notes: 'loud note' } } }), 200);
a.expect(await a.call('POST', `/extended_api/issues/${quietAdmin}/relations.json?notify=false`,
  { data: { relation: { issue_to_id: loudAdmin, relation_type: 'relates' } } }), 201);

// refusal: an outsider cannot create in the private project, quiet or not; nothing is sent
const refused = await a.call('POST', '/extended_api/issues.json?notify=false',
  { as: 'outsider', data: { issue: { project_id: 'e2e-private', tracker_id: 1, subject: `E2E hook outsider ${stamp}` } } });
a.check(refused.status >= 400, `outsider in the private project: HTTP ${refused.status}`);
await a.show('calls', 'Issue creates and updates with and without notify=false / send_notification=0, as admin, manager and reporter, the core path, and a refused outsider');

await new Promise(r => setTimeout(r, 4000));
for (const r of results) {
  r.received = receiver.hooks.filter(h => h.data?.issue?.id === r.id).map(h => h.type).sort();
  a.check(JSON.stringify(r.received) === JSON.stringify([...r.expected].sort()),
    `${r.label}: webhooks ${JSON.stringify(r.received)}, expected ${JSON.stringify(r.expected)}`);
}
a.check(!receiver.hooks.some(h => (h.data?.issue?.subject || '').includes('outsider')), 'a webhook was sent for the refused outsider request');

await t.page.setContent(`<!doctype html><meta charset="utf-8"><body style="font:14px sans-serif;margin:16px">
  <h1 style="font-size:16px">Webhooks received by the test, per issue (${receiver.hooks.length} in total)</h1>
  <table border="1" cellpadding="6" style="border-collapse:collapse">
  <tr><th>issue</th><th>user</th><th>request</th><th>expected</th><th>received</th></tr>
  ${results.map(r => `<tr><td>#${r.id} ${r.label}</td><td>${r.as}</td><td><code>POST ${r.path}</code></td>
    <td>${r.expected.join(', ') || 'none'}</td><td>${r.received.join(', ') || 'none'}</td></tr>`).join('\n')}
  <tr><td>refused</td><td>outsider</td><td><code>POST /extended_api/issues.json?notify=false</code> (e2e-private)</td><td>none</td>
    <td>HTTP ${refused.status}, ${receiver.hooks.some(h => (h.data?.issue?.subject || '').includes('outsider')) ? 'sent' : 'none'}</td></tr>
  </table>
  <p>admin quiet also got a note (notify=false) and a relation (notify=false); admin loud got a note without it.</p></body>`);
await t.shot('received', 'notify=false and send_notification=0 send no webhook for any user; without them, and on the core path, the webhooks arrive');

await t.go(`/issues/${quietAdmin}`);
await t.shot('quiet-issue', 'The quiet issue exists with its note and relation; no webhook was sent for any of it');

receiver.close();
await t.done();
