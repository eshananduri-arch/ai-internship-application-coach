/* Frontend integration checks use a synthetic API, never a real resume or database. */
const { chromium } = require('playwright');
const { spawn } = require('node:child_process');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, 'assets/data/roles.json'), 'utf8'));
const letter = name => `Dear Hiring Team,\n\nI am applying for the AI/ML Intern role at NVIDIA. My Python coursework and student project experience have helped me build an interest in practical machine learning. I would welcome the opportunity to contribute these skills while learning from your team.\n\nThrough a small academic project, I practiced preparing datasets, evaluating results, and explaining the limitations of a model. I value careful testing and clear communication, and I would bring that approach to an internship.\n\nThank you for considering my application. I would appreciate the opportunity to discuss how my experience aligns with this role.\n\nSincerely,\n${name}`;
const server = spawn(process.execPath, ['tools/dev-server.mjs', '--port', '0'], { cwd: root, stdio: ['ignore', 'pipe', 'inherit'] });
let browser;
let checks = 0;
function check(value, description) { assert.ok(value, description); checks++; console.log('PASS ' + description); }
async function visible(page, id) { await page.locator('#fr-' + id).waitFor({ state: 'visible' }); }

(async () => {
  const url = await new Promise((resolve, reject) => {
    let output = '';
    server.stdout.on('data', chunk => { output += chunk; const match = output.match(/http:\/\/127\.0\.0\.1:\d+\//); if (match) resolve(match[0]); });
    server.on('error', reject); server.on('exit', code => reject(new Error('Dev server exited: ' + code)));
  });
  const edge = process.env.PLAYWRIGHT_EXECUTABLE_PATH || (process.platform === 'win32' ? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' : '');
  browser = await chromium.launch({ headless: true, ...(edge && fs.existsSync(edge) ? { executablePath: edge } : {}) });
  const context = await browser.newContext({ colorScheme: 'light' });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  let sessionFailures = 0, sessionRequests = 0;
  let offline = true, failApproval = false, polls = 0, analysis = 0, saved = null, requests = [], wrongRole = false;
  await page.route('**/api/**', async route => {
    const req = route.request();
    const pathname = new URL(req.url()).pathname.replace('/api', '');
    const reply = (data, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(data) });
    if (offline) return reply({ message: 'Backend not connected', code: 'database_unconfigured' }, 503);
    if (pathname === '/session') {
      sessionRequests++;
      if (sessionFailures-- > 0) return route.fulfill({ status: 502, contentType: 'text/html', body: '<h1>Bad Gateway</h1>' });
      return reply({ csrf_token: 'synthetic-csrf' });
    }
    if (pathname === '/companies') return reply([...new Set(catalog.map(row => row.company))].map(name => ({ name })));
    if (pathname === '/roles') return reply(catalog.filter(row => row.company === new URL(req.url()).searchParams.get('company')));
    if (pathname === '/analyses' && req.method() === 'POST') {
      check(req.headers()['x-csrf-token'] === 'synthetic-csrf', 'analysis uses CSRF protection');
      check(!!req.headers()['idempotency-key'], 'analysis carries an idempotency key');
      check(req.postDataBuffer().includes(Buffer.from('synthetic-resume.docx')), 'current uploaded resume is sent');
      check(req.postDataBuffer().includes(Buffer.from('NVIDIA-01')), 'selected role is sent');
      analysis++; requests.push(req.postDataBuffer().toString());
      return reply({ analysis_id: 'analysis-' + analysis, status: 'processing', stage: 'Reviewing your draft' }, 202);
    }
    if (/^\/analyses\/[^/]+$/.test(pathname)) {
      polls++;
      return reply({ analysis_id: 'analysis-' + analysis, status: 'ready', result: { company: 'NVIDIA', role_id: wrongRole ? 'NVIDIA-02' : 'NVIDIA-01', final_letter: letter(analysis === 1 ? 'Taylor Student' : 'Jordan Student'), draft_version: 1, approval_allowed: true } });
    }
    if (pathname.endsWith('/decision')) {
      const body = req.postDataJSON();
      check(req.headers()['x-csrf-token'] === 'synthetic-csrf', 'decision uses CSRF protection');
      if (body.decision === 'reject') return reply({ status: 'rejected' });
      if (failApproval) return reply({ message: 'Database is unavailable. Please retry.' }, 500);
      saved = body.final_letter;
      return reply({ status: 'approved', application_id: 'application-1', final_letter: saved });
    }
    if (pathname.endsWith('/download')) {
      const format = new URL(req.url()).searchParams.get('format');
      if (format === 'pdf') return route.fulfill({ contentType: 'application/pdf', body: Buffer.from('%PDF-1.4\nsynthetic browser download fixture') });
      if (format === 'docx') return route.fulfill({ contentType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', body: Buffer.from('PK\x03\x04synthetic browser download fixture') });
      return route.fulfill({ contentType: 'text/plain; charset=utf-8', body: saved });
    }
    return reply({ message: 'Unexpected request' }, 404);
  });
  await page.goto(url);
  await page.locator('#fr-catalog-status').filter({ hasText: 'Local role catalog' }).waitFor();
  check(await page.locator('#fr-review').isHidden() && await page.locator('#fr-approved').isHidden(), 'initial page contains no generated letter');
  check(await page.locator('#fr-company option').count() === 6, 'all five companies are available');
  for (const company of new Set(catalog.map(row => row.company))) {
    await page.selectOption('#fr-company', company);
    check(await page.locator('#fr-role option').count() === 4, company + ' has three dependent roles');
  }
  await page.click('#fr-generate');
  check((await page.textContent('#fr-input-error')).includes('Upload'), 'missing resume is rejected');
  await page.setInputFiles('#fr-file', { name: 'invalid.txt', mimeType: 'text/plain', buffer: Buffer.from('text') });
  check((await page.textContent('#fr-input-error')).includes('PDF or DOCX'), 'unsupported extension is rejected');
  await page.setInputFiles('#fr-file', { name: 'large.pdf', mimeType: 'application/pdf', buffer: Buffer.alloc(5 * 1024 * 1024 + 1) });
  check((await page.textContent('#fr-input-error')).includes('5 MB'), 'oversize file is rejected');
  async function fill(name = 'Taylor Student') {
    await page.setInputFiles('#fr-file', { name: 'synthetic-resume.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', buffer: Buffer.from('synthetic test content, not a real document') });
    await page.selectOption('#fr-company', 'NVIDIA'); await page.selectOption('#fr-role', 'NVIDIA-01');
    await page.fill('#fr-name', name);
  }
  await fill();
  await page.click('#fr-generate');
  await visible(page, 'input-error');
  check((await page.textContent('#fr-input-error')).toLowerCase().includes('backend'), 'offline generation fails honestly without a fake letter');
  offline = false; sessionFailures = 2;
  await page.click('#fr-generate');
  await page.locator('#fr-connection-status').filter({ hasText: 'Waiting for the server' }).waitFor();
  check(await page.isDisabled('#fr-generate') && analysis === 0, 'startup wait disables duplicate submissions and does not upload yet');
  check(await page.locator('#fr-input-error').isHidden(), 'transient gateway failures show a connection status rather than an immediate error');
  await visible(page, 'review');
  check(sessionRequests === 3 && analysis === 1, 'two startup 502 responses recover into exactly one resume upload');
  check(await page.locator('#fr-connection-status').isHidden(), 'startup status clears after connection');
  check(polls > 0, 'processing response is polled until ready');
  check((await page.textContent('#fr-letter-body')).includes('Taylor Student'), 'review displays the current backend result');
  check(await page.locator('#fr-letter-body .fr-body').first().evaluate(el => getComputedStyle(el).textAlign) === 'justify', 'letter body is justified');
  check(await page.locator('#fr-letter-body .fr-greeting').evaluate(el => getComputedStyle(el).textAlign) === 'left', 'greeting stays left aligned');
  await page.check('#fr-confirm');
  check(await page.isEnabled('#fr-approve'), 'approval requires explicit review');
  await page.click('#fr-edit');
  await page.fill('#fr-editor', letter('Taylor Student') + '\n\n[your email]');
  check(!await page.isChecked('#fr-confirm') && !await page.isEnabled('#fr-approve'), 'editing invalidates approval and placeholders block saving');
  await page.fill('#fr-editor', 'word '.repeat(251));
  check((await page.textContent('#fr-review-error')).includes('250'), 'overlong letters cannot be approved');
  const exact = letter('Taylor Student').replace('My Python coursework', 'My Python coursework <img src=x onerror=alert(1)>');
  await page.fill('#fr-editor', exact); await page.click('#fr-edit');
  check(await page.locator('#fr-letter-body img').count() === 0, 'letter HTML is rendered safely as plain text');
  await page.check('#fr-confirm'); failApproval = true;
  await page.click('#fr-approve');
  await page.locator('#fr-review-error').filter({ hasText: 'Database is unavailable' }).waitFor();
  check(await page.locator('#fr-approved').isHidden(), 'failed save never exposes an approved download');
  failApproval = false;
  await page.click('#fr-approve'); await visible(page, 'approved');
  check(saved === exact && (await page.textContent('#fr-final-letter')).includes('<img'), 'saved and displayed wording matches exact approved edits');
  await page.selectOption('#fr-download-format', 'txt');
  const pendingDownload = page.waitForEvent('download'); await page.click('#fr-download');
  const download = await pendingDownload;
  check(fs.readFileSync(await download.path(), 'utf8') === exact, 'download contains the approved wording');
  for (const [format, signature] of [['pdf', '%PDF-'], ['docx', 'PK']]) {
    await page.selectOption('#fr-download-format', format);
    check(await page.inputValue('#fr-download-format') === format, format + ' download format is selectable');
    const pending = page.waitForEvent('download');
    await page.click('#fr-download');
    const file = await pending;
    check(file.suggestedFilename().endsWith('.' + format), format + ' download uses the selected file extension');
    check(fs.readFileSync(await file.path()).subarray(0, signature.length).toString() === signature, format + ' download preserves the backend file bytes');
  }

  for (const width of [320, 360, 768, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    check(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), 'layout fits viewport ' + width);
  }
  await page.setViewportSize({ width: 1280, height: 1000 });
  await page.click('#fr-new');
  check(await page.locator('#fr-letter-body').textContent() === '', 'new application clears the previous letter');
  await fill('Jordan Student'); await page.click('#fr-generate'); await visible(page, 'review');
  check((await page.textContent('#fr-letter-body')).includes('Jordan Student'), 'second uploaded resume uses a fresh analysis');
  await page.click('#fr-reject'); await visible(page, 'rejected');
  check(await page.locator('#fr-approved').isHidden(), 'rejection does not show a saved application');
  await page.click('#fr-restart'); await fill(); wrongRole = true;
  await page.click('#fr-generate'); await visible(page, 'processing-error');
  check((await page.textContent('#fr-processing-error')).includes('does not match'), 'mismatched role response is blocked');
  await page.click('#fr-processing-back');
  await page.screenshot({ path: process.env.FRONTEND_SCREENSHOT || path.join(require('node:os').tmpdir(), 'firstrole-frontend.png'), fullPage: true });
  check(errors.length === 0, 'no browser JavaScript errors: ' + errors.join(', '));
  console.log(`Frontend checks complete: ${checks} passed. These use mocked backend responses.`);
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  if (browser) await browser.close();
  server.kill();
});
