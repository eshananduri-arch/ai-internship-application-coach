import * as api from '../api.js';
import { state, el, message, show, letterIssue, renderLetter } from '../state.js';
import { refreshReview } from './review.js';

async function decision(choice) {
  if (state.busy || !state.analysisId) return;
  if (choice === 'approve' && (!el('confirm').checked || letterIssue(state.letter) || !state.approvalAllowed)) return;
  state.busy = true;
  el('edit').disabled = true; el('editor').disabled = true; el('back').disabled = true;
  el('confirm').disabled = true;
  refreshReview();
  message('review-error');
  el('decision-status').textContent = choice === 'approve' ? 'Saving your approved version…' : 'Recording your decision…';
  const snapshot = state.letter;
  const body = { decision: choice, final_letter: snapshot, draft_version: state.draftVersion };
  const serialized = JSON.stringify(body);
  if (serialized !== state.decisionBody) { state.decisionBody = serialized; state.decisionKey = crypto.randomUUID(); }
  try {
    const receipt = await api.decide(state.analysisId, body, state.decisionKey);
    if (choice === 'reject') {
      if (receipt.status !== 'rejected') throw new Error('The backend did not confirm the rejection. Try again.');
      state.letter = ''; state.analysisId = '';
      show('rejected');
    } else {
      if (receipt.status !== 'approved' || !receipt.application_id) throw new Error('The backend did not confirm that your application was saved.');
      if (receipt.final_letter !== undefined && String(receipt.final_letter).replace(/\r\n/g, '\n') !== snapshot) throw new Error('The saved wording differs from your approved version. Please contact support before downloading.');
      state.applicationId = String(receipt.application_id);
      state.approvedLetter = snapshot;
      el('final-name').textContent = state.input.candidate_name;
      el('final-role').textContent = state.input.role_title + ' · ' + state.input.company;
      renderLetter(el('final-letter'), snapshot);
      message('download-note', 'Download the exact version you approved.');
      show('approved');
    }
  } catch (error) {
    message('review-error', error.message);
    el('decision-status').textContent = 'Your decision was not confirmed. You can safely retry.';
  } finally {
    state.busy = false;
    el('edit').disabled = false; el('editor').disabled = false; el('back').disabled = false;
    el('confirm').disabled = false;
    el('approve').disabled = !el('confirm').checked || !!letterIssue(state.letter) || !state.approvalAllowed;
    el('reject').disabled = false;
  }
}
export function setupApproval() {
  el('approve').addEventListener('click', () => decision('approve'));
  el('reject').addEventListener('click', () => decision('reject'));
}
