// Carry only validated review scope across Access login. Never accept a redirect URL.
export function reviewQuery(search) {
  const input = new URLSearchParams(search), output = new URLSearchParams();
  const from = Date.parse(input.get('from') ?? ''), to = Date.parse(input.get('to') ?? '');
  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to || to - from > 7 * 86400000) return '';
  output.set('from', new Date(from).toISOString());
  output.set('to', new Date(to).toISOString());
  for (const key of ['participant', 'review']) {
    const value = input.get(key);
    if (value && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(value)) output.set(key, value.toLowerCase());
  }
  return `?${output}`;
}
