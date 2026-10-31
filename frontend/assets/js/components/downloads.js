import * as api from '../api.js';
import { state, el, message } from '../state.js';

const types = {
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  pdf: 'application/pdf', txt: 'text/plain',
};
export function setupDownloads() {
  el('download').addEventListener('click', async () => {
    if (!state.applicationId || state.busy) return;
    state.busy = true; el('download').disabled = true;
    try {
      const format = el('download-format').value;
      if (!types[format]) throw new Error('Choose a supported download format.');
      const response = await api.download(state.applicationId, format);
      const mime = response.headers.get('content-type')?.split(';')[0].trim();
      if (mime !== types[format]) throw new Error('The backend returned an unexpected file type. The download was cancelled.');
      const blob = await response.blob();
      if (!blob.size) throw new Error('The returned file was empty. Please try again.');
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `${state.input.candidate_name}-${state.input.company}-cover-letter.${format}`.replace(/[^a-zA-Z0-9._-]/g, '_');
      document.body.append(anchor); anchor.click(); anchor.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30000);
      message('download-note', 'Your approved cover letter has been downloaded.');
    } catch (error) { message('download-note', error.message); }
    finally { state.busy = false; el('download').disabled = false; }
  });
  el('copy').addEventListener('click', async () => {
    if (!state.applicationId || !state.approvedLetter) return;
    try { await navigator.clipboard.writeText(state.approvedLetter); message('download-note', 'Approved letter copied.'); }
    catch { message('download-note', 'Clipboard access is unavailable. Select the letter to copy it, or download the file.'); }
  });
}
