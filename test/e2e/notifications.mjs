// notify=false (or send_notification=0) through /extended_api: no mail for an
// issue create or update or a relation change; without it Redmine mails as usual.
// Mails land in redmine/tmp/mails, one file per recipient.
import fs from 'node:fs';
import path from 'node:path';
import { e2e } from '../../.codex/e2e/lib.mjs';
import api from './support/api.cjs';

const t = await e2e('notifications');
const { client, setApiSettings } = api;
const a = client(t);
const stamp = Date.now() % 1000000;
const dir = path.join(process.env.REDMINE_DIR || 'redmine', 'tmp', 'mails');
const wait = ms => new Promise(r => setTimeout(r, ms));

// number of mails (Subject: lines) mentioning the marker, over all recipients
function mailsAbout(marker) {
  if (!fs.existsSync(dir)) return 0;
  return fs.readdirSync(dir).reduce((n, f) =>
    n + fs.readFileSync(path.join(dir, f), 'utf8').split('\n').filter(l => l.startsWith('Subject:') && l.includes(marker)).length, 0);
}

await setApiSettings(t, { rest: true });
const users = a.expect(await a.call('GET', '/extended_api/users.json?limit=100'), 200).json?.users || [];
const manager = users.find(u => u.login === 'manager')?.id;
const issue = (subject, query = '') => a.call('POST', `/extended_api/issues.json${query}`,
  { data: { issue: { project_id: 'e2e-project', tracker_id: 1, subject, assigned_to_id: manager } } });

const quiet = a.expect(await issue(`E2E quiet ${stamp}`, '?notify=false'), 201).json?.issue;
const loud = a.expect(await issue(`E2E loud ${stamp}`), 201).json?.issue;
await wait(4000);
const createQuiet = mailsAbout(`E2E quiet ${stamp}`);
const createLoud = mailsAbout(`E2E loud ${stamp}`);
a.check(createQuiet === 0, `create with notify=false: ${createQuiet} mail(s)`);
a.check(createLoud > 0, 'create without notify=false: no mail (is mail delivery to tmp/mails working?)');

a.expect(await a.call('PUT', `/extended_api/issues/${quiet?.id}.json?send_notification=0`, { data: { issue: { notes: 'quiet note' } } }), 200);
a.expect(await a.call('PUT', `/extended_api/issues/${loud?.id}.json`, { data: { issue: { notes: 'loud note' } } }), 200);
const rel = a.expect(await a.call('POST', `/extended_api/issues/${quiet?.id}/relations.json?notify=false`, { data: { relation: { issue_to_id: quiet?.id + 0 === loud?.id ? null : loud?.id, relation_type: 'relates' } } }), 201);
await wait(4000);
const updQuiet = mailsAbout(`E2E quiet ${stamp}`);
const updLoud = mailsAbout(`E2E loud ${stamp}`);
a.check(updQuiet === 0, `update/relation with notify=false: ${updQuiet} mail(s) about the quiet issue`);
a.check(updLoud === createLoud + 1, `loud update: ${updLoud - createLoud} new mail(s), expected 1 (the relation on the loud issue must not mail either)`);
a.expect(await a.call('DELETE', `/extended_api/relations/${rel.json?.relation?.id}.json?notify=false`), 204);
await wait(3000);
a.check(mailsAbout(`E2E quiet ${stamp}`) === 0 && mailsAbout(`E2E loud ${stamp}`) === updLoud, 'relation delete with notify=false sent mail');
await a.show('calls', 'Issue create, update and relation create/delete with notify=false / send_notification=0, next to the same calls without it');

await t.page.setContent(`<!doctype html><meta charset="utf-8"><body style="font:14px sans-serif;margin:16px">
  <h1 style="font-size:16px">Mails written to redmine/tmp/mails, counted per issue</h1>
  <table border="1" cellpadding="6" style="border-collapse:collapse">
  <tr><th>issue</th><th>after create</th><th>after note + relation</th><th>after relation delete</th></tr>
  <tr><td>E2E quiet ${stamp} (notify=false everywhere)</td><td>${createQuiet}</td><td>${updQuiet}</td><td>${mailsAbout(`E2E quiet ${stamp}`)}</td></tr>
  <tr><td>E2E loud ${stamp} (no notify parameter on create and note)</td><td>${createLoud}</td><td>${updLoud}</td><td>${mailsAbout(`E2E loud ${stamp}`)}</td></tr>
  </table></body>`);
await t.shot('mail-count', 'No mail at all for the issue handled with notify=false; the other one mails on create and on its note only');

await t.login('manager');
await t.go(`/issues/${quiet?.id}`);
a.check(await t.page.locator('#relations', { hasText: `E2E loud ${stamp}` }).count() === 0, 'the relation is still shown after delete');
await t.shot('quiet-issue', 'The quiet issue as the assignee sees it: created, noted and related without a mail');

await t.done();
