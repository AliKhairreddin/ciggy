import { useEffect, useRef, useState } from 'react';
import { Button } from './ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from './ui/card';
import { Input } from './ui/input';
import { Label } from './ui/label';
import { Textarea } from './ui/textarea';
import { NativeSelect } from './ui/native-select';
import { api } from '../lib/journal';
import { timeInput } from '../lib/period';
import { coverageEvidence, feedbackReasons, makeFeedbackExport } from '../lib/feedback';
import { reviewQuery } from '../../public/review-link.js';
import { LIMITS, validateRecording } from '../../public/data.js';

export function ReviewFeedback({ state, journal, selection, onDirtyChange }) {
  const [draft, setDraft] = useState(null), [saved, setSaved] = useState([]), [error, setError] = useState('');
  const [busy, setBusy] = useState(false), [loaded, setLoaded] = useState(false), [file, setFile] = useState(null);
  const [reload, setReload] = useState(0);
  const container = useRef(null);
  const connected = state.mode === 'connected';
  const participant = draft?.participantID ?? state.filters.participant;
  const ready = [...state.overviews.values()].filter(item => item.participantID === participant);
  const start = Date.parse(draft?.start ?? ''), end = Date.parse(draft?.end ?? '');
  const relevant = state.sessions.filter(item => item.participantID === participant);
  const complete = !state.busy && !state.hydrating && relevant.every(item => state.overviews.has(item.id)) && loaded;
  const coverage = Number.isFinite(start) && start < end ? coverageEvidence(ready, start, end, complete) : null;
  useEffect(() => { onDirtyChange(Boolean(draft) || busy); }, [draft, busy, onDirtyChange]);
  useEffect(() => {
    if (selection) {
      setDraft(previous => ({ id: crypto.randomUUID(), participantID: state.filters.participant,
        count: 1, reason: 'unknown', notes: '', ...previous,
        start: timeInput(selection[0]), end: timeInput(selection[1]) }));
      setFile(null);
      container.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }, [selection]);
  useEffect(() => {
    let cancelled = false;
    setLoaded(false);
    setFile(null);
    if (!connected) return;
    const query = new URLSearchParams({ from: new Date(state.range[0]).toISOString(), to: new Date(state.range[1]).toISOString() });
    if (state.filters.participant) query.set('participant', state.filters.participant);
    api(`/api/review-feedback?${query}`).then(result => {
      if (!Array.isArray(result.feedback)) throw new Error('Feedback could not be read.');
      if (!cancelled) { setSaved(result.feedback); setLoaded(true); setError(''); }
    }).catch(cause => { if (!cancelled) setError(cause.message); });
    return () => { cancelled = true; };
  }, [connected, state.range, state.filters.participant, reload]);
  const change = (key, value) => { setDraft({ ...draft, [key]: value }); setFile(null); };
  async function save(event) {
    event.preventDefault(); setBusy(true); setError('');
    try {
      if (!draft.participantID) throw new Error('Choose the tester whose cigarette was missed.');
      if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end || start < state.range[0] || end > state.range[1])
        throw new Error('Choose an interval inside the displayed period. Change the period first if needed.');
      const observation = { id: draft.id, participantID: draft.participantID, start, end,
        missedCount: Number(draft.count), reason: draft.reason, notes: draft.notes,
        reviewID: new URLSearchParams(reviewQuery(location.search)).get('review') };
      await api('/api/review-feedback', { method: 'POST', body: JSON.stringify(observation) });
      setDraft(null); setFile(null); setReload(value => value + 1);
      journal.notice('Missed-cigarette feedback saved. Use Adjust count in Ciggy to change your total.');
    } catch (cause) { setError(cause.message); }
    finally { setBusy(false); }
  }
  async function prepareExport(observation) {
    setBusy(true); setError(''); setFile(null);
    try {
      // Read the exact interval, independently of an older period's metadata.
      // A failed or partial page must never produce a misleading empty export.
      const query = new URLSearchParams({ from: new Date(observation.start).toISOString(), to: new Date(observation.end).toISOString(),
        participant: observation.participantID, limit: '200' });
      const rows = [], cursors = new Set(); let cursor;
      do {
        if (cursor) query.set('cursor', cursor);
        const page = await api(`/api/recordings?${query}`);
        if (!Array.isArray(page.recordings)) throw new Error('The recording list could not be read.');
        rows.push(...page.recordings); cursor = page.nextCursor;
        if (cursor && (!page.recordings.length || cursors.has(cursor) || rows.length >= 1000))
          throw new Error('The recording list is incomplete or too large. Choose a shorter interval.');
        if (cursor) cursors.add(cursor);
      } while (cursor);
      const sessions = []; let total = 0;
      for (const row of rows) {
        const session = await api(`/api/recordings/${encodeURIComponent(row.id)}`);
        if (!session.recording?.samples?.length || session.participantID !== observation.participantID)
          throw new Error('A recording could not be verified. Retry the export.');
        session.recording = validateRecording(session.recording);
        if (session.recording.samples.length !== row.sampleCount)
          throw new Error('A recording is incomplete. Retry the export; no partial evidence file was created.');
        total += session.recording.samples.length;
        if (total > LIMITS.totalSamples) throw new Error('Too much motion for one export. Choose a shorter interval.');
        sessions.push(session);
      }
      const data = makeFeedbackExport(observation, sessions, { delivery: state.delivery });
      data.deliveryStatus = state.deliveryError ? 'last-known-report-refresh-failed' : 'last-reported';
      const output = new File([JSON.stringify(data)], `ciggy-feedback-${observation.id}.json`, { type: 'application/json' });
      if (output.size > LIMITS.datasetBytes) throw new Error('This export is too large. Choose a shorter interval.');
      setFile(output);
    } catch (cause) { setError(cause.message); }
    finally { setBusy(false); }
  }
  async function share() {
    try {
      if (navigator.canShare?.({ files: [file] })) await navigator.share({ files: [file], title: 'Ciggy tester feedback' });
      else {
        const url = URL.createObjectURL(file), anchor = document.createElement('a');
        anchor.href = url; anchor.download = file.name; anchor.click();
        setTimeout(() => URL.revokeObjectURL(url), 10000);
      }
    } catch (cause) { if (cause.name !== 'AbortError') setError(cause.message); }
  }
  return <Card ref={container} className="shadow-none" id="missed-cigarette-feedback">
    <CardHeader>
      <CardTitle>Something slipped through?</CardTitle>
      <CardDescription>Report a missed cigarette, including periods with no uploaded motion. Saved privately for 14 days. Export the evidence to share with Codex.</CardDescription>
    </CardHeader>
    <CardContent className="space-y-4">
      <p className="text-xs text-muted-foreground">Missing uploads can mean delayed delivery, sharing being off, expired data, or a capture gap. Your observation helps investigate; it does not establish the cause or change your cigarette total.</p>
      {!connected && <p role="status">Sign in to the private workspace to save tester feedback.</p>}
      {!draft ? <Button disabled={!connected || busy || state.busy} onClick={() => {
        setDraft({ id: crypto.randomUUID(), participantID: state.filters.participant, start: timeInput(state.range[0]),
          end: timeInput(state.range[1]), count: 1, reason: 'unknown', notes: '' }); setFile(null);
      }}>Report a missed cigarette</Button> : <form onSubmit={save} className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2"><Label htmlFor="feedback-tester">Tester</Label><NativeSelect id="feedback-tester" required value={draft.participantID} onChange={e => change('participantID', e.target.value)} disabled={busy}>
            <option value="">Choose a tester</option>{state.participants.map(item => <option key={item.id} value={item.id}>{item.alias}</option>)}
          </NativeSelect></div>
          <div className="space-y-2"><Label htmlFor="feedback-count">Missed cigarettes</Label><Input id="feedback-count" type="number" min="1" max="100" required value={draft.count} onChange={e => change('count', e.target.value)} disabled={busy}/></div>
          <div className="space-y-2"><Label htmlFor="feedback-start">Start · local time</Label><Input id="feedback-start" type="datetime-local" step="0.001" required value={draft.start} onChange={e => change('start', e.target.value)} disabled={busy}/></div>
          <div className="space-y-2"><Label htmlFor="feedback-end">End · local time</Label><Input id="feedback-end" type="datetime-local" step="0.001" required value={draft.end} onChange={e => change('end', e.target.value)} disabled={busy}/></div>
        </div>
        <p role="status" className="text-sm">{!participant ? 'Choose a tester to inspect coverage.' : coverage?.status === 'incomplete' ? 'Coverage is still loading or incomplete. Do not assume there was no tracking.' : coverage?.status === 'uploaded-motion-available' ? 'Uploaded motion overlaps this interval. It may still contain gaps.' : 'No uploaded motion is visible for this interval.'}</p>
        <div className="space-y-2"><Label htmlFor="feedback-reason">What did you observe?</Label><NativeSelect id="feedback-reason" value={draft.reason} onChange={e => change('reason', e.target.value)} disabled={busy}>{Object.entries(feedbackReasons).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</NativeSelect></div>
        <div className="space-y-2"><Label htmlFor="feedback-notes">Notes for the investigation</Label><Textarea id="feedback-notes" maxLength={2000} value={draft.notes} onChange={e => change('notes', e.target.value)} disabled={busy} placeholder="For example: sitting down, Watch on smoking hand; cigarette from 5:45 to 5:50."/></div>
        <div className="flex flex-wrap gap-2"><Button type="submit" disabled={busy}>Save feedback</Button><Button type="button" variant="outline" disabled={busy} onClick={() => setDraft(null)}>Cancel feedback</Button></div>
      </form>}
      {error && <p role="alert" className="text-sm">{error} <Button variant="ghost" size="sm" disabled={busy} onClick={() => setReload(value => value + 1)}>Retry loading feedback</Button></p>}
      {loaded && saved.length === 0 && <p className="text-sm text-muted-foreground">No saved misses in this period.</p>}
      {!loaded && connected && <p role="status" className="text-sm">Saved feedback is not yet loaded for this period.</p>}
      {loaded && saved.map(item => <div key={item.id} className="space-y-2 rounded-lg border p-3 text-sm">
        <p className="font-medium">{state.participants.find(person => person.id === item.participantID)?.alias ?? 'Tester'} · {item.missedCount} missed</p>
        <p>{new Date(item.start).toLocaleString()} – {new Date(item.end).toLocaleString()}</p>
        <p>{feedbackReasons[item.reason]}</p>{item.notes && <p className="whitespace-pre-wrap">{item.notes}</p>}
        <div className="flex flex-wrap gap-2"><Button size="sm" variant="outline" disabled={busy || Boolean(draft)} onClick={() => prepareExport(item)}>Prepare evidence file</Button>
        <Button size="sm" variant="ghost" disabled={busy || Boolean(draft)} onClick={async () => {
          setBusy(true); setError('');
          try { await api(`/api/review-feedback/${item.id}`, { method: 'DELETE' }); setFile(null); setReload(value => value + 1); }
          catch (cause) { setError(cause.message); } finally { setBusy(false); }
        }}>Delete feedback</Button></div>
      </div>)}
      {busy && <p role="status" className="text-sm">Working…</p>}
      {file && <div className="space-y-2 rounded-lg border p-3"><p className="text-sm">Evidence file ready: feedback, available raw motion, coverage gaps, labels and last reported delivery status. Attach this JSON file to Codex for investigation.</p><Button onClick={share}>Share or download evidence</Button></div>}
    </CardContent>
  </Card>;
}
