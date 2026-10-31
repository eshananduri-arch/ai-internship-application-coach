const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createHash, randomBytes } = require('node:crypto');
const assert = require('node:assert/strict');
const dir = path.resolve(__dirname, '..');
const workflow = JSON.parse(fs.readFileSync(path.join(dir, '../Workflow 2 Internship Career Tools.json'), 'utf8'));
let checks = 0;
function check(value, name) { assert.ok(value, name); checks++; }
const nodes = Object.fromEntries(workflow.nodes.map(node => [node.name, node]));
check(workflow.active === false, 'inactive import');
check(new Set(workflow.nodes.map(node => node.id)).size === workflow.nodes.length, 'unique node IDs');
for (const node of workflow.nodes) {
  check(!node.credentials, 'no credentials embedded: ' + node.name);
  check(Array.isArray(node.position) && node.position.length === 2, 'canvas position: ' + node.name);
}
check(nodes['MCP Server'].parameters.authentication === 'headerAuth', 'authenticated MCP');
check(nodes['MCP Server'].parameters.path === 'internship-career-tools', 'stable path');
const search = nodes.search_internship_roles;
check(search.type === '@n8n/n8n-nodes-langchain.vectorStorePGVector', 'persistent PGVector search');
check(search.parameters.mode === 'retrieve-as-tool', 'tool mode');
check(search.parameters.tableName === 'internship_role_chunks', 'database table');
check(search.parameters.includeDocumentMetadata === true, 'sources included');
const filters = search.parameters.options.metadata.metadataValues;
check(filters.some(filter => filter.name === 'dataset' && filter.value === 'internship_roles'), 'dataset filter');
check(filters.some(filter => filter.name === 'role_id' && filter.value.includes("$fromAI('role_id'")), 'exact role filter');
check(nodes['Gemini Embeddings'].parameters.modelName === 'models/gemini-embedding-001', 'fixed embedding model');
for (const [from, connections] of Object.entries(workflow.connections)) {
  check(!!nodes[from], 'connection source exists');
  for (const [kind, sets] of Object.entries(connections)) for (const set of sets) for (const connection of set) {
    check(!!nodes[connection.node] && connection.type === kind, 'connection target/type');
  }
}
for (const name of ['search_internship_roles', 'days_until', 'word_count']) {
  check(workflow.connections[name].ai_tool[0][0].node === 'MCP Server', name + ' exposed');
}
const fakeNow = new Date('2026-10-30T10:00:00Z').getTime();
class FixedDate extends Date { constructor(...args) { super(...(args.length ? args : [fakeNow])); } static now() { return fakeNow; } }
function tool(name, input, clock = FixedDate) {
  const schema = JSON.parse(nodes[name].parameters.inputSchema);
  check(schema.type === 'object' && schema.required.includes('input'), 'structured schema: ' + name);
  const result = vm.runInNewContext('(function(){' + nodes[name].parameters.jsCode + '\n})()', { query: input, Date: clock, Intl }, { timeout: 1000 });
  return JSON.parse(result);
}
for (const [date, expected] of [['2026-12-15',46], ['2026-10-30',0], ['2026-10-29',-1], ['2028-02-29',487]]) {
  const result = tool('days_until', { input: date });
  check(result.ok && result.days_remaining === expected, 'calendar difference: ' + date);
  check(result.today === '2026-10-30' && result.timezone === 'Asia/Kolkata', 'timezone current date');
}
for (const invalid of ['', '2026-02-29', '2026-13-01', '2026-04-31', 'tomorrow', '2026-01-01T00:00:00Z', '0000-01-01']) {
  check(tool('days_until', { input: invalid }).ok === false, 'invalid date rejected');
}
class IndiaMidnightDate extends Date { constructor(...args) { super(...(args.length ? args : ['2026-10-30T20:00:00Z'])); } }
check(tool('days_until', { input: '2026-10-31' }, IndiaMidnightDate).days_remaining === 0, 'India day differs from UTC day');
check(tool('word_count', {}).ok === false, 'missing text rejected');
check(tool('word_count', { input: 'x'.repeat(20001) }).ok === false, 'oversized text rejected');
const texts = ['', 'abc', '  Hello\tworld\nnew paragraph  ', 'Dear Team,\r\n\r\nA letter.\rSincerely,\nTaylor', 'Résumé — తెలుగు हिन्दी 😀', '\ud800', 'word '.repeat(250), 'word '.repeat(251)];
for (let i = 0; i < 40; i++) texts.push(randomBytes(i * 19).toString('base64') + ' 😀\nOne more word.');
for (const text of texts) {
  const result = tool('word_count', { input: text });
  const normalized = text.replace(/\r\n?/g, '\n');
  const expected = normalized.trim() ? normalized.trim().split(/\s+/u).length : 0;
  check(result.word_count === expected, 'exact whitespace count');
  check(result.text_sha256 === createHash('sha256').update(normalized, 'utf8').digest('hex'), 'SHA-256 matches platform implementation');
  check(result.within_limit === (expected <= 250) && result.nonempty === (expected > 0), 'word-limit and empty-text flags');
}
const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, 'roles_catalog.json'), 'utf8'));
check(catalog.length === 15 && new Set(catalog.map(role => role.role_id)).size === 15, '15 unique catalog IDs');
for (const role of catalog) check(/^[A-Z]+-\d{2}$/.test(role.role_id), 'catalog matches exact role-ID contract: ' + role.role_id);
check(!workflow.nodes.some(node => /memory|vectorStoreInMemory/i.test(node.type)), 'no in-memory knowledge');
check(Object.keys(workflow.pinData).length === 0, 'no pinned data');
console.log(JSON.stringify({ passed: checks, live_n8n_tested: false, database_tested: false, note: 'Local code and workflow-structure checks only. Live credentials, import and retrieval still require the new account.' }, null, 2));
