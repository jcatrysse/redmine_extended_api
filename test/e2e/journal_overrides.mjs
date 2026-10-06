// Journal import overrides through /extended_api: an admin sets the user and
// dates of the journal an update creates, and gets the journal back in the
// answer; for anybody else, or on the core path, the journal is the normal one.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('journal-overrides');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

await setApiSettings(t, { rest: true });
const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const uid = login => users.find(u => u.login === login)?.id;
const issue = a.expect(await a.call('POST', '/extended_api/issues.json?notify=false', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E journals ${stamp}` } },
}), 201).json?.issue;

const imported = a.expect(await a.call('PATCH', `/extended_api/issues/${issue?.id}.json?notify=false`, {
  data: { issue: { notes: `Imported worklog ${stamp}`, journal: { user_id: uid('reporter'), updated_by_id: uid('reporter'), created_on: '2021-01-01T10:00:00Z', updated_on: '2021-01-01T11:00:00Z' } } },
}), 200);
const j = imported.json?.journal;
a.check(imported.mode === 'extended' && j?.notes === `Imported worklog ${stamp}`, `admin update: answer ${imported.text.slice(0, 200)}`);
a.check(j?.user?.id === uid('reporter') && j?.created_on === '2021-01-01T10:00:00Z', `admin update: journal user ${j?.user?.id}, created_on ${j?.created_on}`);
const top = a.expect(await a.call('PATCH', `/extended_api/issues/${issue?.id}.json`, {
  data: { issue: { notes: `Top-level journal key ${stamp}` }, journal: { user_id: uid('manager'), created_on: '2021-02-02T10:00:00Z' } },
}), 200);
a.check(top.json?.journal?.user?.id === uid('manager') && top.json?.journal?.created_on === '2021-02-02T10:00:00Z', `top-level journal key: ${top.text.slice(0, 200)}`);
const read = a.expect(await a.call('GET', `/extended_api/issues/${issue?.id}.json?include=journals`), 200).json?.issue?.journals || [];
a.check(read.some(x => x.user?.id === uid('reporter') && x.created_on === '2021-01-01T10:00:00Z'), 'read back: the imported journal is not stored as given');
await a.show('admin', 'Admin adds a note as reporter dated 2021-01-01 (nested under issue) and one as manager (top-level journal key): the answer is the journal, stored as given');

await t.go(`/issues/${issue?.id}`);
a.check(await t.page.locator('.journal', { hasText: `Imported worklog ${stamp}` }).locator('h4', { hasText: 'Reporter E2E' }).count() > 0, 'issue page: the imported note is not by Reporter E2E');
await t.shot('history', 'The issue history: the imported notes by Reporter E2E and Manager E2E, years ago, though the admin posted them');

const byManager = a.expect(await a.call('PATCH', `/extended_api/issues/${issue?.id}.json`, {
  as: 'manager', data: { issue: { notes: `Manager note ${stamp}` }, journal: { user_id: uid('reporter'), created_on: '2021-01-01T10:00:00Z' } },
}), 200);
a.check(byManager.json?.journal?.user?.id === uid('manager') && !byManager.json?.journal?.created_on?.startsWith('2021'), `manager: journal ${JSON.stringify(byManager.json?.journal?.user)} ${byManager.json?.journal?.created_on}`);
const core = a.expect(await a.call('PUT', `/issues/${issue?.id}.json`, {
  data: { issue: { notes: `Core note ${stamp}` }, journal: { user_id: uid('reporter'), created_on: '2021-01-01T10:00:00Z' } },
}), 204, 'core path answers 204 without a body');
const last = (a.expect(await a.call('GET', `/extended_api/issues/${issue?.id}.json?include=journals`), 200).json?.issue?.journals || []).at(-1);
a.check(last?.notes === `Core note ${stamp}` && last?.user?.id === uid('admin'), `core path: last journal ${JSON.stringify(last?.user)}`);
// a non-member may add notes in a public project (core "Non member" role); on the private
// project he is refused; both exactly as on the core path
const privIssue = (a.expect(await a.call('GET', '/extended_api/issues.json?project_id=e2e-private&limit=1'), 200).json?.issues || [])[0];
for (const [path, label] of [[`/issues/${issue?.id}.json`, 'public project'], [`/issues/${privIssue?.id}.json`, 'private project']]) {
  const c = await a.call('PUT', path, { as: 'outsider', data: { issue: { notes: `outsider ${label}` } } });
  const x = await a.call('PATCH', '/extended_api' + path, { as: 'outsider', data: { issue: { notes: `outsider ${label}` }, journal: { user_id: uid('admin') } } });
  a.check((c.status < 300) === (x.status < 300) && (label === 'public project' ? x.status === 200 : x.status === 403),
    `outsider, ${label}: core ${c.status}, extended ${x.status}`);
  if (x.status === 200) a.check(x.json?.journal?.user?.id === uid('outsider'), 'outsider: journal override applied');
}
const noChange = a.expect(await a.call('PATCH', `/extended_api/issues/${issue?.id}.json`, { data: { issue: {} } }), 204, 'nothing to journal: no journal, as core');
await a.show('ignored', 'Manager (no admin): his own journal, now; core path: 204 and the admin\'s journal; outsider like on the core path (note allowed in the public project, 403 in the private one, override ignored); an update without changes answers 204 like core');
a.check(core.text === '', 'core path: unexpected body');
a.check(noChange.text === '', 'empty update: unexpected body');

await t.login('manager');
await t.go(`/issues/${issue?.id}`);
await t.shot('history-member', 'The same history seen by a member: imported notes keep their user and date, the manager\'s own note is "just now"');

await t.done();
