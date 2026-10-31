export const state = {
  file: null, rows: [], input: null, analysisId: '', applicationId: '',
  letter: '', approvedLetter: '', editing: false, busy: false,
  approvalAllowed: true, draftVersion: null, decisionKey: '', decisionBody: '',
};
export const el = name => document.getElementById('fr-' + name);
export function message(name, text = '') { el(name).textContent = text; el(name).hidden = !text; }
export function show(name) {
  for (const section of ['intake', 'processing', 'review', 'approved', 'rejected']) el(section).hidden = section !== name;
  for (const step of document.querySelectorAll('[data-step]')) {
    const current = step.dataset.step === (name === 'processing' ? 'intake' : name);
    if (current) step.setAttribute('aria-current', 'step'); else step.removeAttribute('aria-current');
  }
  const heading = el(name).querySelector('h1,h2');
  if (heading) { heading.tabIndex = -1; heading.focus({ preventScroll: true }); }
  window.scrollTo({ top: 0, behavior: 'instant' });
}
export const words = text => text.trim().split(/\s+/u).filter(Boolean).length;
export function letterIssue(text) {
  if (text.trim().length < 80) return 'The letter is too short. Review and complete it before approval.';
  if (words(text) > 250) return 'Please shorten the letter to 250 words or fewer before approval.';
  if (/\[(?:your|candidate|name|company|role|date|address|email|phone|insert)[^\]]*\]|<(?:EMAIL_ADDRESS|PHONE_NUMBER|NAME|PERSON)>/i.test(text)) return 'Replace the remaining placeholders before approval.';
  return '';
}
export function renderLetter(target, text) {
  target.replaceChildren();
  let closing = false;
  text.replace(/\r\n/g, '\n').trim().split(/\n\s*\n/).forEach((part, index) => {
    const p = document.createElement('p');
    closing ||= /^(sincerely|yours(?: sincerely| faithfully| truly)?|best regards|kind regards|regards)[,\s]/i.test(part) || /^thank you[,!]?(?:\n|$)/i.test(part);
    p.className = closing ? 'fr-closing' : (index === 0 && /^(dear|to the|hello)\b/i.test(part) ? 'fr-greeting' : 'fr-body');
    p.textContent = part;
    target.append(p);
  });
}
