import { state, el, message, show, words, letterIssue, renderLetter } from '../state.js';

export function refreshReview() {
  renderLetter(el('letter-body'), state.letter);
  el('word-count').textContent = words(state.letter) + ' / 250 words';
  const issue = letterIssue(state.letter) || (!state.approvalAllowed ? 'The backend review requires changes before this draft can be approved.' : '');
  message('review-error', issue);
  el('approve').disabled = state.busy || !el('confirm').checked || !!issue;
  el('reject').disabled = state.busy;
}
export function presentReview(data) {
  const result = data.result || data;
  const id = data.analysis_id || result.analysis_id;
  if (!id || typeof result.final_letter !== 'string' || !result.final_letter.trim()) throw new Error('No complete cover letter was returned. Nothing has been approved or saved.');
  if (result.company !== state.input.company || result.role_id !== state.input.role_id) throw new Error('The returned role does not match your selection. Nothing has been approved or saved.');
  state.analysisId = id;
  state.letter = result.final_letter.replace(/\r\n/g, '\n').trim();
  state.approvalAllowed = result.approval_allowed !== false;
  state.draftVersion = result.draft_version ?? null;
  state.editing = false;
  state.decisionKey = ''; state.decisionBody = '';
  el('editor').value = state.letter;
  el('editor').hidden = true; el('letter-body').hidden = false;
  el('edit').textContent = 'Edit letter';
  el('confirm').checked = false;
  el('review-name').textContent = state.input.candidate_name;
  el('review-role').textContent = state.input.role_title + ' · ' + state.input.company;
  el('summary-company').textContent = state.input.company;
  el('summary-role').textContent = state.input.role_title;
  el('summary-file').textContent = state.fileName;
  const feedback = result.critic_review?.feedback;
  el('edit-status').textContent = 'Ready for your review';
  el('decision-status').textContent = Array.isArray(feedback) && feedback.length ? 'Reviewer: ' + feedback.filter(value => typeof value === 'string').join(' ') : 'Only your approved version will be saved.';
  refreshReview();
  show('review');
}
export function setupReview() {
  el('confirm').addEventListener('change', refreshReview);
  el('edit').addEventListener('click', () => {
    state.editing = !state.editing;
    el('editor').hidden = !state.editing; el('letter-body').hidden = state.editing;
    el('edit').textContent = state.editing ? 'Done editing' : 'Edit letter';
    if (state.editing) el('editor').focus(); else refreshReview();
  });
  el('editor').addEventListener('input', () => {
    state.letter = el('editor').value;
    el('confirm').checked = false;
    el('edit-status').textContent = 'Edited · please review again';
    refreshReview();
  });
}
