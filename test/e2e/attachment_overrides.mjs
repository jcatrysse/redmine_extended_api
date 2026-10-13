// Attachment import overrides through /extended_api/uploads: an admin sets the
// author and creation date of an upload; for anybody else, or on the core path,
// the uploader and now are kept.
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('attachment-overrides');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;

await setApiSettings(t, { rest: true });
const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const uid = login => users.find(u => u.login === login)?.id;
const body = Buffer.from(`legacy log ${stamp}\n`);

const up = a.expect(await a.call('POST', `/extended_api/uploads.json?filename=legacy-${stamp}.txt&attachment[author_id]=${uid('manager')}&attachment[created_on]=2019-09-09T09:09:09Z`, { body }), 201);
const token = up.json?.upload?.token;
const issue = a.expect(await a.call('POST', '/extended_api/issues.json?notify=false', {
  data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject: `E2E attachment ${stamp}`, uploads: [{ token, filename: `legacy-${stamp}.txt`, content_type: 'text/plain' }] } },
}), 201).json?.issue;
const att = (a.expect(await a.call('GET', `/extended_api/issues/${issue?.id}.json?include=attachments`), 200).json?.issue?.attachments || [])[0];
a.check(att?.author?.id === uid('manager') && att?.created_on === '2019-09-09T09:09:09Z', `admin upload: author ${JSON.stringify(att?.author)}, created_on ${att?.created_on}`);
await a.show('admin', 'Admin uploads a file with author manager and a 2019 date, attaches it to a new issue; the attachment keeps both');

await t.go(`/issues/${issue?.id}`);
a.check(await t.page.locator('.attachments', { hasText: 'Manager E2E' }).count() > 0, 'issue page: the attachment is not by Manager E2E');
await t.shot('issue-page', 'The issue page lists the attachment by Manager E2E, dated 2019');

const mUp = a.expect(await a.call('POST', `/extended_api/uploads.json?filename=m-${stamp}.txt&attachment[author_id]=${uid('reporter')}&attachment[created_on]=2019-09-09T09:09:09Z`, { as: 'manager', body }), 201);
const mIssue = a.expect(await a.call('PUT', `/extended_api/issues/${issue?.id}.json`, {
  as: 'manager', data: { issue: { notes: 'manager file', uploads: [{ token: mUp.json?.upload?.token, filename: `m-${stamp}.txt` }] } },
}), 200);
const coreUp = a.expect(await a.call('POST', `/uploads.json?filename=c-${stamp}.txt&attachment[author_id]=${uid('manager')}&attachment[created_on]=2019-09-09T09:09:09Z`, { body }), 201);
a.expect(await a.call('PUT', `/extended_api/issues/${issue?.id}.json`, {
  data: { issue: { uploads: [{ token: coreUp.json?.upload?.token, filename: `c-${stamp}.txt` }] } },
}), 200);
const atts = a.expect(await a.call('GET', `/extended_api/issues/${issue?.id}.json?include=attachments`), 200).json?.issue?.attachments || [];
const m = atts.find(x => x.filename === `m-${stamp}.txt`);
const c = atts.find(x => x.filename === `c-${stamp}.txt`);
a.check(m?.author?.id === uid('manager') && !m?.created_on?.startsWith('2019'), `manager upload: ${JSON.stringify(m?.author)} ${m?.created_on}`);
a.check(c?.author?.id === uid('admin') && !c?.created_on?.startsWith('2019'), `core upload: ${JSON.stringify(c?.author)} ${c?.created_on}`);
a.check(!!mIssue, '');
await a.show('ignored', 'Manager (no admin) and the core path /uploads.json: the overrides are ignored, the uploader and today are kept');

const bad = a.expect(await a.call('POST', `/extended_api/uploads.json?filename=bad-${stamp}.txt&attachment[created_on]=yesterday-ish`, { body }), 422, 'bad created_on');
a.check(bad.json?.errors?.[0] === 'Created is invalid', `bad created_on: ${bad.text}`);
a.expect(await a.call('POST', `/extended_api/uploads.json?filename=bad-${stamp}.txt&attachment[author_id]=999999`, { body }), 422, 'unknown author');
a.expect(await a.call('POST', `/extended_api/uploads.json?filename=x-${stamp}.txt`, { as: null, body }), 401, 'anonymous');
a.expect(await a.call('POST', `/extended_api/uploads.json?filename=x-${stamp}.txt`, { as: 'outsider', body }), 201, 'any logged in user may upload, as in core');
await a.show('refused', 'Refusals: unparseable created_on and unknown author (422, no file stored), anonymous (401); outsider may upload like on the core path');

await t.login('manager');
await t.go(`/issues/${issue?.id}`);
await t.shot('issue-page-member', 'Seen by manager: the imported file by Manager E2E (2019), his own and the core upload with today');

await t.done();
