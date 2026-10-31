import * as api from './api.js';
import { state, el, message, show } from './state.js';
import { setupIntake, loadCatalog } from './components/intake.js';
import { setupReview, presentReview, refreshReview } from './components/review.js';
import { setupApproval } from './components/approval.js';
import { setupDownloads } from './components/downloads.js';

let operation = 0;
let controller;
const delay = (ms, signal) => new Promise((resolve, reject) => {
  const abort = () => { clearTimeout(timer); reject(new DOMException('Aborted', 'AbortError')); };
  const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, ms);
  signal.addEventListener('abort', abort, { once: true });
});

async function consume(data, token, signal) {
  const started = Date.now();
  while (token === operation && !signal.aborted) {
    if (data.status === 'failed' || data.status === 'error') throw new Error(typeof data.message === 'string' ? data.message.slice(0, 300) : 'The analysis failed. Please try again.');
    if (data.status === 'ready' || data.result?.final_letter || data.final_letter) {
      state.busy = false;
      presentReview(data);
      state.file = null; el('file').value = '';
      return;
    }
    if (!['queued', 'processing'].includes(data.status) || !data.analysis_id) throw new Error('The backend returned an unexpected analysis status.');
    state.analysisId = String(data.analysis_id);
    el('processing-stage').textContent = typeof data.stage === 'string' ? data.stage.slice(0, 180) : 'Drafting and reviewing your cover letter…';
    if (Date.now() - started > 180000) throw new Error('This is taking longer than expected. Check the status again without uploading another résumé.');
    await delay(1500, signal);
    const next = await api.status(state.analysisId, signal);
    data = { ...next, analysis_id: next.analysis_id || state.analysisId };
  }
}
async function generate() {
  const token = ++operation;
  controller?.abort(); controller = new AbortController();
  message('processing-error'); el('check-again').hidden = true;
  el('processing-stage').textContent = 'Submitting your résumé securely…';
  try {
    const data = await api.generate(state.input, state.file, state.input.request_id, controller.signal);
    await consume(data, token, controller.signal);
  } catch (error) {
    if (token === operation) {
      message('processing-error', error.message);
      el('processing-stage').textContent = 'Your analysis has not been confirmed.';
      el('check-again').hidden = !state.analysisId;
    }
  } finally { if (token === operation) { state.busy = false; el('generate').disabled = false; } }
}
function back() {
  ++operation; controller?.abort(); state.busy = false;
  el('generate').disabled = false;
  state.letter = ''; state.analysisId = ''; state.approvedLetter = ''; state.applicationId = '';
  el('letter-body').replaceChildren(); el('final-letter').replaceChildren(); el('editor').value = '';
  el('confirm').checked = false;
  if (!state.file) { el('file-name').textContent = 'Drop your résumé here'; el('file-help').textContent = 'or click to browse · PDF or DOCX · Up to 5 MB'; }
  show('intake');
}
function reset() {
  if (state.busy) return;
  state.file = null; el('form').reset(); el('file').value = '';
  el('role').replaceChildren(new Option('Choose company first', '')); el('role').disabled = true;
  message('input-error'); back();
}

setupIntake(generate); setupReview(); setupApproval(); setupDownloads();
for (const name of ['back', 'processing-back']) el(name).addEventListener('click', back);
for (const name of ['new', 'restart']) el(name).addEventListener('click', reset);
el('check-again').addEventListener('click', async () => {
  if (state.busy || !state.analysisId) return;
  const token = ++operation;
  controller?.abort(); controller = new AbortController();
  state.busy = true; el('check-again').hidden = true; message('processing-error');
  try { const data = await api.status(state.analysisId, controller.signal); await consume({ ...data, analysis_id: data.analysis_id || state.analysisId }, token, controller.signal); }
  catch (error) { if (token === operation) { message('processing-error', error.message); el('check-again').hidden = false; } }
  finally { if (token === operation) { state.busy = false; refreshReview(); } }
});
loadCatalog();
