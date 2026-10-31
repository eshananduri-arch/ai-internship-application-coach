import { state, el, message, show } from '../state.js';
import * as api from '../api.js';

export function setupIntake(onGenerate) {
  el('upload').addEventListener('click', () => el('file').click());
  function setFiles(files) {
    state.file = null;
    message('input-error');
    if (files.length !== 1) { message('input-error', 'Please upload exactly one résumé.'); return; }
    const file = files[0];
    if (!/\.(pdf|docx)$/i.test(file.name)) { message('input-error', 'Choose a PDF or DOCX résumé.'); return; }
    if (!file.size || file.size > 5 * 1024 * 1024) { message('input-error', 'Choose a non-empty résumé up to 5 MB.'); return; }
    state.file = file;
    el('file-name').textContent = file.name;
    el('file-help').textContent = `${Math.ceil(file.size / 1024)} KB · Click to replace`;
  }
  el('file').addEventListener('change', event => setFiles(event.target.files));
  el('upload').addEventListener('dragover', event => { event.preventDefault(); });
  el('upload').addEventListener('drop', event => { event.preventDefault(); setFiles(event.dataTransfer.files); });
  el('company').addEventListener('change', () => {
    el('role').replaceChildren(new Option('Choose role', ''));
    const rows = state.rows.filter(row => row.company === el('company').value);
    for (const row of rows) el('role').add(new Option(row.role, row.role_id));
    el('role').disabled = !rows.length;
    el('role-details').textContent = 'Choose the role you want to apply for.';
  });
  el('role').addEventListener('change', () => {
    const row = state.rows.find(row => row.role_id === el('role').value);
    el('role-details').textContent = row ? [row.location, row.deadline ? 'Apply by ' + row.deadline : ''].filter(Boolean).join(' · ') : '';
  });
  el('form').addEventListener('submit', async event => {
    event.preventDefault();
    if (state.busy) return;
    message('input-error');
    if (!state.file) return message('input-error', 'Upload your résumé first.');
    const row = state.rows.find(row => row.company === el('company').value && row.role_id === el('role').value);
    if (!row) return message('input-error', 'Choose a company and internship role.');
    const name = el('name').value.trim();
    if (name.length < 2) return message('input-error', 'Enter your full name for the signature.');
    state.busy = true;
    el('generate').disabled = true;
    try {
      await api.session();
      state.input = { request_id: crypto.randomUUID(), company: row.company, role_id: row.role_id, role_title: row.role, candidate_name: name };
      state.fileName = state.file.name;
      state.letter = ''; state.approvedLetter = ''; state.applicationId = ''; state.analysisId = '';
      show('processing');
      await onGenerate();
    } catch (error) {
      show('intake');
      message('input-error', error.message);
    } finally {
      state.busy = false;
      el('generate').disabled = false;
    }
  });
}

export async function loadCatalog() {
  el('generate').disabled = true;
  try {
    const { rows, offline } = await api.catalog();
    state.rows = rows;
    el('company').replaceChildren(new Option('Choose company', ''));
    for (const company of new Set(rows.map(row => row.company))) el('company').add(new Option(company, company));
    el('catalog-status').textContent = offline ? 'Local role catalog. Generation and saving require the Python backend.' : 'Role catalog connected.';
    el('generate').disabled = false;
  } catch (error) { message('input-error', error.message); }
}
