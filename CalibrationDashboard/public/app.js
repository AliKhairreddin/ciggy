import { appleSecondsToMs, msToAppleSeconds, cleanAlias, parseImport, mergeSessions, validateAnnotation, validateRecording,
  coverageRanges, coveredDuration, makeExport, magnitude, LIMITS, mergeRemotePage } from './data.js';
import { loadSessions, saveSessions } from './storage.js';

const $ = id => document.getElementById(id);
const colors = ['#ffb885', '#c2e0b8', '#baa8eb', '#ffc952', '#78c5ce', '#ee8ca1'];
const state = { sessions: [], cache: new Map(), compared: new Set(), active: '', editing: null,
  connected: false, view: null, selection: null, files: [], email: '', loading: false, dirty: false };
let lastFullRemoteLoad = 0;
const filterIDs = ['participantFilter', 'periodFilter', 'dayFilter', 'sourceFilter'];
let appliedFilters = Object.fromEntries(filterIDs.map(id => [id, $(id).value]));
const timeFormat = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
const shortTime = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit', second: '2-digit' });
const aliases = () => [...new Set(state.sessions.map(session => session.participant))].sort();
const colorIndexFor = alias => Math.abs([...alias].reduce((hash, character) => ((hash * 31) + character.charCodeAt(0)) | 0, 0)) % colors.length;
const colorFor = alias => colors[colorIndexFor(alias)];
const bounds = session => session.recording
  ? [appleSecondsToMs(session.recording.samples[0].timestamp), appleSecondsToMs(session.recording.samples.at(-1).timestamp)]
  : [Date.parse(session.startedAt), Date.parse(session.endedAt)];
const samples = session => session.recording?.samples ?? [];
const sources = session => session.sources ?? [...new Set(samples(session).map(sample => sample.source))];
const sourceName = value => value === 'recordedAccelerometer' ? 'Background history' : 'Live Watch motion';
function showStatus(message, error = false) { $('status').textContent = message; $('status').hidden = !message; $('status').classList.toggle('error', error); }
function node(tag, text, className) { const element = document.createElement(tag); if (text != null) element.textContent = text; if (className) element.className = className; return element; }
function timeInput(ms) { const date = new Date(ms); return new Date(ms - date.getTimezoneOffset() * 60000).toISOString().slice(0, 23); }
function duration(milliseconds) { const minutes = milliseconds / 60000; return minutes < 1 ? `${Math.round(milliseconds / 1000)}s` : minutes < 60 ? `${Math.round(minutes)}m` : `${(minutes / 60).toFixed(1)}h`; }
function periodBounds() {
  const now = Date.now(), today = new Date(); today.setHours(0, 0, 0, 0);
  switch ($('periodFilter').value) {
    case 'today': return [today.getTime(), now];
    case 'yesterday': { const yesterday = new Date(today); yesterday.setDate(yesterday.getDate() - 1); return [yesterday.getTime(), today.getTime()]; }
    case 'day': { const day = new Date(`${$('dayFilter').value}T00:00:00`); const end = new Date(day); end.setDate(end.getDate() + 1); return [day.getTime(), end.getTime()]; }
    case 'all': {
      const times = state.sessions.flatMap(bounds).filter(Number.isFinite);
      return times.length ? [Math.min(...times), Math.max(...times)] : [now - 48 * 3600000, now];
    }
    default: return [now - 48 * 3600000, now];
  }
}
function visibleSessions() {
  const [from, to] = periodBounds();
  return state.sessions.filter(session => {
    const [start, end] = bounds(session);
    return end >= from && start <= to && (!$('participantFilter').value || session.participant === $('participantFilter').value) &&
      (!$('sourceFilter').value || sources(session).includes($('sourceFilter').value));
  }).sort((a, b) => bounds(b)[0] - bounds(a)[0]);
}
async function api(path, options = {}) {
  const response = await fetch(path, { credentials: 'same-origin', ...options, headers: { 'Content-Type': 'application/json', ...options.headers } });
  const type = response.headers.get('content-type') ?? '';
  const body = type.includes('application/json') ? await response.json() : null;
  if (response.status === 409) throw new Error('Another reviewer changed these labels. Refresh recordings before trying again.');
  if (!response.ok || !body) throw new Error(body?.error ?? 'The private workspace could not be reached. Sign in again or try refreshing.');
  return body;
}
async function loadRemote({ incremental = false } = {}) {
  if (state.loading) return;
  state.loading = true;
  for (const id of ['periodFilter', 'dayFilter', 'refreshButton']) $(id).disabled = true;
  try {
    let results = []; let cursor = null; const seenCursors = new Set();
    const nowMs = Date.now(), [fromMs, toMs] = $('periodFilter').value === 'all'
      ? [nowMs - 14 * 86400000, nowMs] : periodBounds();
    if (![fromMs, toMs].every(Number.isFinite) || fromMs > toMs) throw new Error('Choose a valid time period.');
    const recentOnly = incremental && lastFullRemoteLoad > 0 && nowMs - lastFullRemoteLoad < 5 * 60000;
    do {
      const query = new URLSearchParams({ from: new Date(fromMs).toISOString(), to: new Date(toMs).toISOString(), limit: '200' });
      if (cursor) query.set('cursor', cursor);
      const page = await api(`/api/recordings?${query}`);
      if (!Array.isArray(page.recordings)) throw new Error('The recording list could not be read.');
      results.push(...page.recordings.map(session => ({ ...session, remote: true })));
      cursor = page.nextCursor;
      if (cursor && (!page.recordings.length || seenCursors.has(cursor))) throw new Error('The recording list was incomplete. Previously loaded data is kept; try Refresh.');
      if (cursor) seenCursors.add(cursor);
      if (recentOnly) {
        results = mergeRemotePage(state.sessions, results, { hasMore: Boolean(cursor), fromMs, toMs, nowMs });
        break;
      }
      if (results.length >= 12000 && cursor) throw new Error('Too many recordings for one view. Choose a specific day or a shorter time period; all saved data is kept.');
    } while (cursor);
    for (const session of results) {
      const cached = state.cache.get(session.id);
      if (cached && (cached.labelRevision !== session.labelRevision || cached.participant !== session.participant) && state.editing == null && !state.dirty) state.cache.delete(session.id);
    }
    state.sessions = results;
    if (!recentOnly) lastFullRemoteLoad = nowMs;
    $('connectionStatus').textContent = 'Private · connected';
  } finally {
    state.loading = false;
    for (const id of ['periodFilter', 'dayFilter', 'refreshButton']) $(id).disabled = false;
  }
}
async function getSession(id) {
  if (state.cache.has(id)) return state.cache.get(id);
  const metadata = state.sessions.find(session => session.id === id);
  if (!metadata) throw new Error('This recording is no longer available.');
  const session = metadata.remote ? { ...await api(`/api/recordings/${encodeURIComponent(id)}`), remote: true } : metadata;
  // Validate downloaded data with the same limits as explicit file imports.
  session.recording = validateRecording(session.recording);
  state.cache.set(id, session);
  if (state.cache.size > 25) {
    for (const key of state.cache.keys()) {
      if (key !== state.active && !state.compared.has(key)) { state.cache.delete(key); break; }
    }
  }
  return session;
}
function render() {
  const selectedAlias = $('participantFilter').value;
  $('participantFilter').replaceChildren(new Option('Everyone', ''));
  aliases().forEach(alias => $('participantFilter').append(new Option(alias, alias)));
  if (aliases().includes(selectedAlias)) $('participantFilter').value = selectedAlias;
  const visible = visibleSessions();
  $('recordingCount').textContent = visible.length.toLocaleString();
  $('participantCount').textContent = new Set(visible.map(session => session.participant)).size;
  const [fromMs, toMs] = periodBounds();
  const coverage = coveredDuration(visible.map(session => state.cache.get(session.id) ?? session).filter(session => session.recording), fromMs, toMs);
  const unloaded = visible.filter(session => session.remote && !state.cache.has(session.id)).length;
  $('coverageCount').previousElementSibling.textContent = unloaded ? 'Motion samples' : 'Recorded time';
  $('coverageCount').textContent = unloaded ? new Intl.NumberFormat(undefined, { notation: 'compact', maximumFractionDigits: 1 }).format(visible.reduce((sum, session) => sum + (session.sampleCount ?? samples(session).length), 0)) : duration(coverage);
  $('coverageCount').nextElementSibling.textContent = unloaded ? 'Open a recording to inspect coverage' : 'Excludes gaps and overlapping sources';
  $('annotationCount').textContent = visible.reduce((sum, session) => sum + (state.cache.get(session.id)?.annotations.length ?? session.annotationCount ?? session.annotations?.length ?? 0), 0);
  $('visibleCount').textContent = visible.length;
  $('emptyState').hidden = visible.length > 0;
  $('chartWorkspace').hidden = visible.length === 0;
  $('exportButton').disabled = visible.length === 0;
  $('recordingSelect').replaceChildren(...(visible.length ? visible.map(session => new Option(`${session.participant} · ${timeFormat.format(bounds(session)[0])}`, session.id)) : [new Option('Import a recording first', '')]));
  const activeVisible = visible.some(session => session.id === state.active);
  $('recordingSelect').disabled = !visible.length;
  if (activeVisible) $('recordingSelect').value = state.active;
  renderRecordings(visible); renderAnnotations(visible); drawChart();
  if (visible.length && (!activeVisible || !state.cache.has(state.active))) selectRecording(activeVisible ? state.active : visible[0].id).catch(error => showStatus(error.message, true));
  if (!visible.length) { state.active = ''; setFormEnabled(false); }
  appliedFilters = Object.fromEntries(filterIDs.map(id => [id, $(id).value]));
}
function renderRecordings(visible) {
  const list = $('recordingList'); list.replaceChildren();
  if (!visible.length) { list.append(node('p', state.sessions.length ? 'No recordings match these filters.' : 'Your imported recordings will appear here.', 'muted placeholder')); return; }
  visible.forEach(session => {
    const row = node('article', null, `recording-row${session.id === state.active ? ' selected' : ''}`);
    const top = node('div', null, 'recording-top'), dot = node('span', null, `recording-dot participant-color-${colorIndexFor(session.participant)}`);
    const main = node('button', null, 'recording-main'); main.type = 'button';
    main.append(node('strong', session.participant), node('small', `${timeFormat.format(bounds(session)[0])} · ${(session.sampleCount ?? samples(session).length).toLocaleString()} samples`));
    main.onclick = () => selectRecording(session.id, true).catch(error => showStatus(error.message, true));
    top.append(dot, main); row.append(top);
    const controls = node('div', null, 'row-controls');
    controls.append(node('span', sources(session).map(sourceName).join(' + '), 'source-tag'));
    const compare = node('button', state.compared.has(session.id) ? '✓ Comparing' : 'Compare', 'quiet tiny');
    compare.setAttribute('aria-pressed', state.compared.has(session.id));
    compare.onclick = async () => {
      try {
        if (state.compared.has(session.id)) state.compared.delete(session.id);
        else { if (state.compared.size >= 5) throw new Error('Compare up to five recordings at a time.'); await getSession(session.id); state.compared.add(session.id); }
        fitCompared(); render();
      } catch (error) { showStatus(error.message, true); }
    };
    const remove = node('button', 'Remove', 'quiet tiny'); remove.onclick = () => deleteSession(session).catch(error => showStatus(error.message, true));
    controls.append(compare, remove); row.append(controls);
    const aliasRow = node('div', null, 'row-controls'), alias = node('input', null, 'alias-input'); alias.value = session.participant; alias.maxLength = 80; alias.setAttribute('aria-label', 'Participant alias');
    const rename = node('button', 'Rename', 'quiet tiny'); rename.onclick = () => renameParticipant(session, alias.value).catch(error => showStatus(error.message, true));
    aliasRow.append(alias, rename, node('span', session.remote ? 'Shared privately' : 'This browser', 'muted')); row.append(aliasRow); list.append(row);
  });
}
function setFormEnabled(enabled) { ['rangeStart', 'rangeEnd', 'activitySelect', 'annotationNotes', 'saveAnnotation'].forEach(id => $(id).disabled = !enabled); }
async function selectRecording(id, fit = false) {
  state.active = id; state.editing = null; state.dirty = false;
  const session = await getSession(id); if (state.active !== id) return;
  setFormEnabled(true); $('recordingSelect').value = id; $('cancelEdit').hidden = true;
  $('saveAnnotation').textContent = 'Save activity label'; $('annotationNotes').value = '';
  const range = bounds(session); state.selection = range; $('rangeStart').value = timeInput(range[0]); $('rangeEnd').value = timeInput(range[1]);
  if (fit || !state.view) state.view = paddedRange(range);
  render();
}
function paddedRange([start, end]) { const pad = Math.max(1000, (end - start) * .03); return [start - pad, end + pad]; }
function fitCompared() {
  const chosen = [state.active, ...state.compared].map(id => state.cache.get(id)).filter(Boolean);
  if (chosen.length) state.view = paddedRange([Math.min(...chosen.map(session => bounds(session)[0])), Math.max(...chosen.map(session => bounds(session)[1]))]);
}
function renderAnnotations(visible) {
  const rows = visible.flatMap(metadata => {
    const session = state.cache.get(metadata.id) ?? metadata;
    return (session.annotations ?? []).map(annotation => ({ annotation, session }));
  }).sort((a, b) => b.annotation.start - a.annotation.start);
  const unloadedLabels = visible.reduce((count, session) => count + (!state.cache.has(session.id) ? (session.annotationCount ?? 0) : 0), 0);
  $('labelSummary').textContent = `${rows.length} ${rows.length === 1 ? 'label' : 'labels'}${unloadedLabels ? ` · ${unloadedLabels} in unopened recordings` : ''}`;
  const list = $('annotationList'); list.replaceChildren();
  if (!rows.length) { list.append(node('p', unloadedLabels ? 'Open a recording to see and edit its activity labels.' : 'Choose a recording and mark a time range to add your first label.', 'muted placeholder')); return; }
  rows.forEach(({ annotation, session }) => {
    const row = node('article', null, 'annotation-row'), description = node('div', null, 'annotation-description');
    description.append(node('strong', `${session.participant} · ${timeFormat.format(appleSecondsToMs(annotation.start))} – ${shortTime.format(appleSecondsToMs(annotation.end))}`));
    if (annotation.notes) description.append(node('small', annotation.notes));
    const actions = node('div', null, 'annotation-actions'), edit = node('button', 'Edit', 'quiet tiny'), remove = node('button', 'Delete', 'quiet tiny');
    edit.onclick = async () => { await selectRecording(session.id, true); state.editing = annotation.id; state.selection = [appleSecondsToMs(annotation.start), appleSecondsToMs(annotation.end)];
      $('rangeStart').value = timeInput(state.selection[0]); $('rangeEnd').value = timeInput(state.selection[1]); $('activitySelect').value = annotation.label; $('annotationNotes').value = annotation.notes; $('saveAnnotation').textContent = 'Save changes'; $('cancelEdit').hidden = false; $('annotationForm').scrollIntoView({ behavior: 'smooth', block: 'center' }); drawChart(); };
    remove.onclick = () => persistLabels(session, session.annotations.filter(item => item.id !== annotation.id)).then(render).catch(error => showStatus(error.message, true));
    actions.append(edit, remove); row.append(node('span', annotation.label, `activity-pill ${annotation.label}`), description, actions); list.append(row);
  });
}
async function persistLabels(session, annotations) {
  let updated = { ...session, annotations };
  if (session.remote) {
    const result = await api(`/api/recordings/${encodeURIComponent(session.id)}/labels`, { method: 'PUT',
      body: JSON.stringify({ annotations, expectedRevision: session.labelRevision }) });
    updated = { ...updated, annotations: result.annotations ?? annotations, labelRevision: result.labelRevision };
  } else await saveSessions([updated]);
  state.cache.set(session.id, updated);
  state.sessions = state.sessions.map(metadata => metadata.id === session.id ? (session.remote ? { ...metadata, annotationCount: annotations.length, labelRevision: updated.labelRevision } : updated) : metadata);
}
async function renameParticipant(session, value) {
  const alias = cleanAlias(value);
  if (session.remote) {
    await api(`/api/participants/${encodeURIComponent(session.participantID)}`, { method: 'PATCH', body: JSON.stringify({ alias }) });
    state.cache.clear(); await loadRemote();
  } else {
    const updated = { ...session, participant: alias }; await saveSessions([updated]); state.cache.set(session.id, updated);
    state.sessions = state.sessions.map(item => item.id === session.id ? updated : item);
  }
  render(); showStatus('Participant name updated.');
}
async function deleteSession(session) {
  if (!confirm(`Remove this recording and its labels for ${session.participant}? Export a copy first if you want to keep it.`)) return;
  if (session.remote) await api(`/api/recordings/${encodeURIComponent(session.id)}`, { method: 'DELETE' });
  else await saveSessions([], [session.id]);
  state.sessions = state.sessions.filter(item => item.id !== session.id); state.cache.delete(session.id); state.compared.delete(session.id); render();
}
function drawChart() {
  const canvas = $('motionChart'); if ($('chartWorkspace').hidden) return;
  const width = canvas.clientWidth || 800, height = 270, pixel = window.devicePixelRatio || 1;
  canvas.width = width * pixel; canvas.height = height * pixel;
  const context = canvas.getContext('2d'); context.scale(pixel, pixel);
  const css = getComputedStyle(document.body), secondary = css.getPropertyValue('--secondary').trim(), border = css.getPropertyValue('--border').trim();
  const view = state.view ?? periodBounds(), [from, to] = view, span = Math.max(1, to - from), left = 45, right = width - 15, top = 20, bottom = height - 30;
  const x = value => left + (value - from) / span * (right - left);
  const signal = $('signalSelect').value, axis = $('axisSelect').value;
  const chosen = [...new Set([state.active, ...state.compared])].map(id => state.cache.get(id)).filter(Boolean);
  const points = chosen.map(session => ({ session, values: samples(session).filter(sample => {
    const at = appleSecondsToMs(sample.timestamp); return at >= from && at <= to;
  }).map(sample => ({ at: appleSecondsToMs(sample.timestamp), value: axis === 'magnitude' ? magnitude(sample[signal]) : sample[signal]?.[axis] ?? null })) }));
  let low = 0, high = .05, hasSamples = false;
  for (const line of points) for (const point of line.values) if (point.value != null) { low = Math.min(low, point.value); high = Math.max(high, point.value); hasSamples = true; }
  const spread = Math.max(.05, high - low); low -= spread * .08; high += spread * .08;
  const y = value => bottom - (value - low) / (high - low) * (bottom - top);
  context.font = '10px -apple-system, sans-serif';
  for (let index = 0; index <= 4; index++) {
    const vertical = top + index / 4 * (bottom - top); context.strokeStyle = border; context.lineWidth = 1; context.beginPath(); context.moveTo(left, vertical); context.lineTo(right, vertical); context.stroke();
    context.fillStyle = secondary; context.textAlign = 'right'; context.fillText((high - index / 4 * (high - low)).toFixed(2), left - 9, vertical + 3);
    context.textAlign = index === 0 ? 'left' : index === 4 ? 'right' : 'center'; context.fillText(shortTime.format(from + index / 4 * span), left + index / 4 * (right - left), height - 9);
  }
  context.save(); context.beginPath(); context.rect(left, top, right - left, bottom - top); context.clip();
  const active = state.cache.get(state.active);
  if (active) for (const label of active.annotations) {
    context.fillStyle = label.label === 'smoking' ? '#e84d2125' : '#c2e0b818';
    context.fillRect(x(appleSecondsToMs(label.start)), top, Math.max(1, x(appleSecondsToMs(label.end)) - x(appleSecondsToMs(label.start))), bottom - top);
  }
  points.forEach(({ session, values }) => {
    context.strokeStyle = colorFor(session.participant); context.lineWidth = 1.4; context.beginPath(); let last = null;
    // Keep extrema in each horizontal pixel, so brief gestures remain visible.
    let bucket = null;
    const flush = () => { if (!bucket) return; const samples = [bucket.first, bucket.min, bucket.max, bucket.last].sort((a, b) => a.at - b.at); for (const point of samples) { if (last == null || point.at - last > 1000) context.moveTo(x(point.at), y(point.value)); else context.lineTo(x(point.at), y(point.value)); last = point.at; } };
    for (const point of values) {
      if (point.value == null) { flush(); bucket = null; last = null; continue; }
      const column = Math.floor(x(point.at));
      if (!bucket || column !== bucket.column || point.at - bucket.last.at > 1000) { flush(); bucket = { column, first: point, last: point, min: point, max: point }; }
      else { bucket.last = point; if (point.value < bucket.min.value) bucket.min = point; if (point.value > bucket.max.value) bucket.max = point; }
    }
    flush(); context.stroke();
  });
  if (state.selection) { context.fillStyle = '#ffb88520'; context.fillRect(x(state.selection[0]), top, x(state.selection[1]) - x(state.selection[0]), bottom - top); context.strokeStyle = '#ffb88588'; [state.selection[0], state.selection[1]].forEach(at => { context.beginPath(); context.moveTo(x(at), top); context.lineTo(x(at), bottom); context.stroke(); }); }
  context.restore();
  $('chartEmpty').hidden = hasSamples; $('chartEmpty').textContent = signal === 'rotationRate' ? 'No gyroscope readings in this range. Background history does not include them.' : 'No samples in this time range.';
  $('chartRange').textContent = `${timeFormat.format(from)} – ${timeFormat.format(to)}`;
  $('participantLegend').replaceChildren(...chosen.map(session => { const item = node('span'), dot = node('i', null, `participant-color-${colorIndexFor(session.participant)}`); item.append(dot, document.createTextNode(`${session.participant} · ${sourceName(sources(session)[0])}`)); return item; }));
  if (active) { const ranges = coverageRanges(samples(active)); const coverage = ranges.reduce((sum, range) => sum + range.end - range.start, 0); $('coverageNote').textContent = `${active.participant}: ${duration(coverage * 1000)} recorded · ${Math.max(0, ranges.length - 1)} ${ranges.length === 2 ? 'gap' : 'gaps'} longer than one second. Lines stop where samples are missing. Activity labels apply to the selected recording.`; }
}
let dragStart = null;
$('motionChart').addEventListener('pointerdown', event => {
  if (!state.active || !state.view) return; const canvas = $('motionChart'), box = canvas.getBoundingClientRect();
  dragStart = state.view[0] + Math.max(0, Math.min(1, (event.clientX - box.left - 45) / (box.width - 60))) * (state.view[1] - state.view[0]); canvas.setPointerCapture(event.pointerId);
});
$('motionChart').addEventListener('pointermove', event => {
  if (dragStart == null) return; const box = $('motionChart').getBoundingClientRect();
  const end = state.view[0] + Math.max(0, Math.min(1, (event.clientX - box.left - 45) / (box.width - 60))) * (state.view[1] - state.view[0]);
  const range = bounds(state.cache.get(state.active)); state.selection = [Math.max(range[0], Math.min(dragStart, end)), Math.min(range[1], Math.max(dragStart, end))];
  if (state.selection[0] < state.selection[1]) { state.dirty = true; $('cancelEdit').hidden = false; $('rangeStart').value = timeInput(state.selection[0]); $('rangeEnd').value = timeInput(state.selection[1]); }
  drawChart();
});
['pointerup', 'pointercancel'].forEach(name => $('motionChart').addEventListener(name, () => { dragStart = null; }));
$('annotationForm').addEventListener('submit', async event => {
  event.preventDefault(); const button = $('saveAnnotation'); button.disabled = true;
  try {
    const session = await getSession(state.active);
    const rawFirst = session.recording.samples[0].timestamp, rawLast = session.recording.samples.at(-1).timestamp;
    let start = msToAppleSeconds(new Date($('rangeStart').value).getTime());
    let end = msToAppleSeconds(new Date($('rangeEnd').value).getTime());
    // datetime-local offers millisecond precision; preserve the original sensor
    // boundary when its displayed value rounds down by a fraction of a millisecond.
    if (Math.abs(start - rawFirst) < .001) start = rawFirst;
    if (Math.abs(end - rawLast) < .001) end = rawLast;
    const annotation = validateAnnotation({ id: state.editing ?? crypto.randomUUID(), recordingID: session.recording.id,
      start, end,
      label: $('activitySelect').value, notes: $('annotationNotes').value }, session.recording);
    const updated = session.annotations.filter(item => item.id !== annotation.id); updated.push(annotation);
    await persistLabels(session, updated); state.editing = null; state.dirty = false; $('cancelEdit').hidden = true; $('saveAnnotation').textContent = 'Save activity label'; $('annotationNotes').value = ''; render(); showStatus('Activity label saved.');
  } catch (error) { showStatus(error.message, true); } finally { button.disabled = false; }
});
$('cancelEdit').onclick = () => selectRecording(state.active);
$('annotationForm').addEventListener('input', () => { state.dirty = true; $('cancelEdit').hidden = false; });
$('recordingSelect').onchange = () => selectRecording($('recordingSelect').value, true).catch(error => showStatus(error.message, true));
for (const id of ['rangeStart', 'rangeEnd']) $(id).onchange = () => { const range = [new Date($('rangeStart').value).getTime(), new Date($('rangeEnd').value).getTime()]; if (range.every(Number.isFinite) && range[0] < range[1]) { state.selection = range; drawChart(); } };
for (const id of filterIDs) $(id).onchange = async () => {
  $('dayLabel').hidden = $('periodFilter').value !== 'day';
  if (state.dirty) {
    $(id).value = appliedFilters[id]; $('dayLabel').hidden = $('periodFilter').value !== 'day';
    showStatus('Save or reset your current activity label before changing the time period.', true); return;
  }
  try {
    if (state.connected && (id === 'periodFilter' || id === 'dayFilter')) await loadRemote();
    state.view = null; state.compared.clear(); render();
  } catch (error) {
    for (const key of filterIDs) $(key).value = appliedFilters[key];
    $('dayLabel').hidden = $('periodFilter').value !== 'day'; showStatus(error.message, true);
  }
};
for (const id of ['signalSelect', 'axisSelect']) $(id).onchange = drawChart;
$('resetView').onclick = () => { state.view = periodBounds(); drawChart(); };
$('fitRecording').onclick = () => { const session = state.cache.get(state.active); if (session) { state.view = paddedRange(bounds(session)); drawChart(); } };
function zoom(factor) { const range = state.view ?? periodBounds(), middle = (range[0] + range[1]) / 2, span = Math.max(1000, (range[1] - range[0]) * factor); state.view = [middle - span / 2, middle + span / 2]; drawChart(); }
$('zoomIn').onclick = () => zoom(.5); $('zoomOut').onclick = () => zoom(2);
$('importButton').onclick = $('emptyImport').onclick = () => $('fileInput').click();
$('fileInput').onchange = () => { state.files = [...$('fileInput').files]; if (!state.files.length) return; $('importError').hidden = true; $('importDescription').textContent = `${state.files.length} ${state.files.length === 1 ? 'file selected' : 'files selected'}.`; $('importPrivacy').textContent = state.connected ? 'Imports are saved to your private shared workspace and expire after 14 days. Import each person’s files separately.' : 'Imports stay in this browser on this device. Import each person’s files separately.'; $('importDialog').showModal(); $('participantAlias').focus(); };
$('cancelImport').onclick = () => { $('importDialog').close(); $('fileInput').value = ''; };
$('importForm').onsubmit = async event => {
  event.preventDefault(); const button = $('confirmImport'); button.disabled = true;
  try {
    const alias = cleanAlias($('participantAlias').value); const incoming = [];
    for (const file of state.files) { if (file.size > LIMITS.datasetBytes) throw new Error(`${file.name} is larger than 128 MB.`); incoming.push(...parseImport(await file.text(), file.name, alias)); }
    if (state.connected) {
      let added = 0;
      try { for (const session of incoming) { await api('/api/import', { method: 'POST', body: JSON.stringify({ participant: session.participant, recording: session.recording, annotations: session.annotations }) }); added++; } }
      catch (error) { await loadRemote(); render(); throw new Error(`${added} recordings saved before the import stopped. ${error.message}`); }
      state.cache.clear(); await loadRemote(); showStatus(`${added} recordings sent to your private workspace. Existing recordings keep their saved labels.`);
    } else {
      const result = mergeSessions(state.sessions, incoming), added = result.sessions.filter(session => !state.sessions.some(existing => existing.id === session.id));
      await saveSessions(added); state.sessions = result.sessions; added.forEach(session => state.cache.set(session.id, session)); showStatus(`${result.added} recordings imported${result.duplicate ? ` · ${result.duplicate} already in your workspace` : ''}.`);
    }
    $('importDialog').close(); $('fileInput').value = ''; render();
  } catch (error) { $('importError').textContent = error.message; $('importError').hidden = false; showStatus(error.message, true); } finally { button.disabled = false; }
};
$('exportButton').onclick = async () => {
  $('exportButton').disabled = true;
  try {
    const visible = visibleSessions(), selected = []; let total = 0;
    for (const metadata of visible) { const session = await getSession(metadata.id); total += samples(session).length; if (total > LIMITS.totalSamples) throw new Error('This selection is too large for one export. Choose one participant or a single day.'); selected.push(session); }
    const [fromMs, toMs] = periodBounds(); const data = makeExport(selected, { fromMs, toMs });
    const blob = new Blob([JSON.stringify(data)], { type: 'application/json' });
    if (blob.size > LIMITS.datasetBytes) throw new Error('This export is larger than 128 MB. Choose one participant or a shorter date period.');
    const url = URL.createObjectURL(blob), anchor = node('a'); anchor.href = url; anchor.download = `ciggy-labeled-motion-${new Date().toISOString().slice(0, 10)}.json`; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); showStatus(`${data.sessions.length} recordings exported with their activity labels.`);
  } catch (error) { showStatus(error.message, true); } finally { $('exportButton').disabled = false; }
};
$('pairButton').onclick = () => { $('pairError').hidden = true; $('pairDialog').showModal(); $('pairAlias').focus(); };
$('closePair').onclick = () => $('pairDialog').close();
$('pairForm').onsubmit = async event => {
  event.preventDefault(); $('generatePairing').disabled = true;
  try { const result = await api('/api/pairing', { method: 'POST', body: JSON.stringify({ alias: cleanAlias($('pairAlias').value) }) }); $('pairCode').textContent = result.code; $('pairExpiry').textContent = `Expires ${timeFormat.format(new Date(result.expiresAt))}. Use a different code for each iPhone.`; $('pairResult').hidden = false; }
  catch (error) { $('pairError').textContent = error.message; $('pairError').hidden = false; showStatus(error.message, true); } finally { $('generatePairing').disabled = false; }
};
$('refreshButton').onclick = async () => {
  if (state.dirty) { showStatus('Save or reset your current activity label before refreshing.', true); return; }
  $('refreshButton').disabled = true;
  try { await loadRemote(); render(); showStatus('Shared recordings refreshed.'); }
  catch (error) { showStatus(error.message, true); }
  finally { $('refreshButton').disabled = false; }
};
$('themeButton').onclick = () => { document.body.classList.toggle('cream'); const cream = document.body.classList.contains('cream'); localStorage.setItem('ciggy-motion-theme', cream ? 'cream' : 'dark'); $('themeButton').textContent = cream ? '☾' : '☀'; $('themeButton').setAttribute('aria-label', `Switch to ${cream ? 'dark' : 'cream'} appearance`); drawChart(); };
new ResizeObserver(drawChart).observe($('motionChart'));
// Reuse metadata while the tab is hidden or a label is being written. Refreshing
// an open page is bounded and never erases a form in progress on a background tick.
setInterval(async () => {
  if (!state.connected || state.loading || state.dirty || state.editing || document.hidden || document.querySelector('dialog[open]')) return;
  try { await loadRemote({ incremental: true }); render(); }
  catch { $('connectionStatus').textContent = 'Update pending'; }
}, 60000);
async function initialize() {
  if (localStorage.getItem('ciggy-motion-theme') === 'cream') $('themeButton').click();
  $('dayFilter').value = timeInput(Date.now()).slice(0, 10);
  try {
    const response = await fetch('/api/session', { credentials: 'same-origin' });
    if (response.ok && response.headers.get('content-type')?.includes('application/json')) {
      const account = await response.json(); state.connected = true; state.email = account.email; $('pairButton').hidden = false; $('refreshButton').hidden = false;
      $('periodFilter').querySelector('option[value="all"]').textContent = 'Past 14 days';
      $('privacyNote').textContent = `Private shared workspace · ${account.email}. Motion sharing is opt-in on each iPhone. Uploaded recordings and activity labels expire after ${account.retentionDays ?? 14} days. Gaps mean no recorded evidence, not a smoke-free period. Background history has no gyroscope readings.`;
      await loadRemote();
    } else if (response.status === 404) {
      state.sessions = await loadSessions(); state.sessions.forEach(session => state.cache.set(session.id, session)); $('connectionStatus').textContent = 'This browser only';
    } else { throw new Error('Sign in to open the private workspace. Refresh this page to try again.'); }
    render();
  } catch (error) { $('connectionStatus').textContent = 'Connection needed'; showStatus(error.message, true); }
}
initialize();
