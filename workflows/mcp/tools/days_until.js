// n8n Code Tool body. Input schema is { input: "YYYY-MM-DD" }.
const input = typeof query === 'string' ? query : query?.input;
const error = (code, message) => JSON.stringify({ ok: false, error: code, message });
if (typeof input !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input.trim())) {
  return error('INVALID_DATE', 'Send one real calendar date as input, for example 2026-12-15.');
}
const date = input.trim();
const [year, month, day] = date.split('-').map(Number);
if (year < 1000 || year > 9999) return error('INVALID_DATE', 'Use a year between 1000 and 9999.');
const deadline = Date.UTC(year, month - 1, day);
const checked = new Date(deadline);
if (checked.getUTCFullYear() !== year || checked.getUTCMonth() !== month - 1 || checked.getUTCDate() !== day) {
  return error('INVALID_DATE', 'This calendar date does not exist. Send YYYY-MM-DD.');
}
const timezone = 'Asia/Kolkata';
const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', {
  timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit',
}).formatToParts(new Date()).map(part => [part.type, part.value]));
const today = `${parts.year}-${parts.month}-${parts.day}`;
const current = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
const remaining = Math.round((deadline - current) / 86400000);
return JSON.stringify({
  ok: true, deadline: date, today, timezone, days_remaining: remaining,
  expired: remaining < 0, deadline_is_today: remaining === 0,
  rule: 'Calendar-day difference in Asia/Kolkata; the closing hour is not inferred.',
});
