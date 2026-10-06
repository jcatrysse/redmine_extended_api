// Shared by the scenarios in test/e2e/*.mjs. A .cjs file in a subdirectory, so
// that e2e.sh, which runs every test/e2e/**/*.mjs, does not run it as a scenario.
//
// The plugin has no pages of its own: every function is a REST endpoint under
// /extended_api. A scenario calls it through t.page.request (HTTP Basic as one of
// the seeded users), checks status and body, and screenshots two things: the
// request/response exchange rendered as a page, and the Redmine page that shows
// the result (an issue, the admin lists).
const PASSWORD = process.env.RMP_USER_PASSWORD || process.env.RMP_ADMIN_PASSWORD || 'Redmine7Test!';

function basic(login) {
  return 'Basic ' + Buffer.from(`${login}:${PASSWORD}`).toString('base64');
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

function client(t) {
  const log = [];

  // as: a seeded login, or null for an anonymous call. data: a JSON body.
  // body + contentType: a raw body (uploads).
  async function call(method, path, { as = 'admin', data, body, contentType } = {}) {
    const headers = {};
    if (as) headers.Authorization = basic(as);
    const opts = { method, headers, failOnStatusCode: false, maxRedirects: 0 };
    if (data !== undefined) {
      headers['Content-Type'] = 'application/json';
      opts.data = JSON.stringify(data);
    } else if (body !== undefined) {
      headers['Content-Type'] = contentType || 'application/octet-stream';
      opts.data = body;
    }
    const res = await t.page.request.fetch(t.BASE + path, opts);
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { /* not JSON */ }
    const entry = {
      as: as || 'anonymous', method, path, sent: data !== undefined ? data : (body !== undefined ? `<${body.length} bytes>` : undefined),
      status: res.status(), mode: res.headers()['x-redmine-extended-api'] || '', json, text,
    };
    log.push(entry);
    return entry;
  }

  // Records a problem (and so fails the run) when the status is not the expected one.
  function expect(entry, status, what = '') {
    if (entry.status !== status) {
      t.problems.push(`${entry.method} ${entry.path} as ${entry.as}: HTTP ${entry.status}, expected ${status}${what ? ` (${what})` : ''}: ${entry.text.slice(0, 300)}`);
    }
    return entry;
  }

  function check(condition, message) {
    if (!condition) t.problems.push(message);
    return condition;
  }

  // Renders the calls made since the last show() as a page and screenshots it.
  async function show(shotName, caption) {
    const entries = log.splice(0);
    const rows = entries.map(e => {
      // never put a key in a committed screenshot, even a test instance's
      const response = e.json ? JSON.stringify(e.json, (k, v) => (k === 'api_key' ? '[hidden]' : v), 2) : e.text;
      const cut = response.length > 1600 ? response.slice(0, 1600) + '\n...' : response;
      const cls = e.status >= 400 ? 'refused' : 'ok';
      return `<tr><td>${escapeHtml(e.as)}</td><td><code>${escapeHtml(e.method)} ${escapeHtml(e.path)}</code>` +
        (e.sent !== undefined ? `<pre>${escapeHtml(typeof e.sent === 'string' ? e.sent : JSON.stringify(e.sent, null, 2))}</pre>` : '') +
        `</td><td class="${cls}">${e.status}</td><td>${escapeHtml(e.mode)}</td><td><pre>${escapeHtml(cut)}</pre></td></tr>`;
    }).join('\n');
    await t.page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
      body { font: 13px/1.4 sans-serif; margin: 16px; }
      h1 { font-size: 16px; }
      table { border-collapse: collapse; width: 100%; }
      td, th { border: 1px solid #ccc; padding: 4px 6px; vertical-align: top; text-align: left; }
      pre { margin: 2px 0; white-space: pre-wrap; word-break: break-all; font-size: 11px; }
      .ok { background: #e6f4ea; font-weight: bold; } .refused { background: #fde8e8; font-weight: bold; }
    </style></head><body><h1>${escapeHtml(caption)}</h1>
    <table><tr><th>user</th><th>request</th><th>HTTP</th><th>x-redmine-extended-api</th><th>response</th></tr>${rows}</table>
    </body></html>`);
    return t.shot(shotName, caption);
  }

  return { call, expect, check, show };
}

// Turns the REST API (and optionally the webhooks) on or off in Administration >
// Settings > Integrations, through the form, as admin. Leaves the browser logged in as admin.
async function setApiSettings(t, { rest = true, webhooks } = {}) {
  await t.login('admin');
  await t.go('/settings?tab=integrations');
  await t.sudo();
  if (!/tab=integrations/.test(t.page.url())) await t.go('/settings?tab=integrations');
  await t.page.setChecked('#settings_rest_api_enabled', rest);
  if (webhooks !== undefined) await t.page.setChecked('#settings_webhooks_enabled', webhooks);
  await t.page.locator('#settings_rest_api_enabled').locator('xpath=ancestor::form').locator('input[type=submit]').click();
  await t.settle();
  await t.sudo();
  t.check('save API settings');
  if ((await t.page.locator('#settings_rest_api_enabled').isChecked()) !== rest) {
    t.problems.push(`API settings: REST API is not ${rest ? 'on' : 'off'} after saving`);
  }
}

module.exports = { client, setApiSettings, basic };
