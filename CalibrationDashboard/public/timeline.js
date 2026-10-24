// Compact measured ranges, shared by ingestion and browser-only imports. Raw
// recordings stay intact; no interpolation or smoking classification is applied.
const signals = ['userAcceleration', 'gravity', 'rotationRate'];
export function summarizeRecording(recording) {
  const bins = [], ranges = [];
  let bin, range, previous;
  for (const sample of recording.samples) {
    const at = sample.timestamp, source = sample.source ?? 'liveDeviceMotion';
    const interrupted = previous == null || at - previous > 1 || range.source !== source;
    if (interrupted) { range = { start: at, end: at, source }; ranges.push(range); }
    else range.end = at;
    if (!bin || interrupted || Math.floor(at / 5) !== Math.floor(bin.start / 5)) {
      bin = { start: at, end: at, source, count: 0, values: {} }; bins.push(bin);
    }
    bin.end = at; bin.count++;
    for (const signal of signals) {
      const vector = sample[signal]; if (!vector) continue;
      const values = { ...vector, magnitude: Math.hypot(vector.x, vector.y, vector.z) };
      const limits = bin.values[signal] ??= {};
      for (const [axis, value] of Object.entries(values)) {
        const pair = limits[axis];
        limits[axis] = pair ? [Math.min(pair[0], value), Math.max(pair[1], value)] : [value, value];
      }
    }
    previous = at;
  }
  return { version: 1, sampleCount: recording.samples.length, bins, ranges };
}

export function mergeCoverage(ranges, from = -Infinity, to = Infinity) {
  const sorted = ranges.map(range => [Math.max(from, range.start), Math.min(to, range.end)])
    .filter(([start, end]) => end >= start).sort((a, b) => a[0] - b[0]);
  const merged = [];
  for (const [start, end] of sorted) {
    const last = merged.at(-1);
    if (last && start - last[1] <= 1) last[1] = Math.max(last[1], end);
    else merged.push([start, end]);
  }
  return merged;
}

export function timelineExtent(sessions, fallback) {
  const bins = sessions.flatMap(session => session.overview?.bins ?? []);
  if (!bins.length) return fallback;
  const start = Math.min(...sessions.map(session => session.overview?.bins[0]?.start ?? Infinity));
  const end = Math.max(...sessions.map(session => session.overview?.bins.at(-1)?.end ?? -Infinity));
  const padding = Math.max(150000, (end - start) * 1000 * .025);
  const epoch = 978307200000;
  return [start * 1000 + epoch - padding, end * 1000 + epoch + padding];
}
