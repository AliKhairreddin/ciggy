import { appleSecondsToMs, msToAppleSeconds, makeExport } from '../../public/data.js';
import { mergeCoverage, summarizeRecording } from '../../public/timeline.js';

export const feedbackReasons = {
  unknown: 'Not sure why',
  'no-uploaded-motion': 'No uploaded motion visible',
  'motion-present': 'Motion is visible, but Ciggy missed it',
  'watch-not-tracking': 'I observed that tracking was stopped',
};

export function coverageEvidence(sessions, start, end, complete = true) {
  const ranges = mergeCoverage(sessions.flatMap(session =>
    (session.overview ?? summarizeRecording(session.recording)).ranges), msToAppleSeconds(start), msToAppleSeconds(end))
    .map(([a, b]) => [appleSecondsToMs(a), appleSecondsToMs(b)]);
  const gaps = [];
  let cursor = start;
  for (const [a, b] of ranges) {
    if (a > cursor) gaps.push([cursor, a]);
    cursor = Math.max(cursor, b);
  }
  if (cursor < end) gaps.push([cursor, end]);
  return { status: complete ? (ranges.length ? 'uploaded-motion-available' : 'no-uploaded-motion') : 'incomplete',
    availableRangesUnixMs: ranges, unavailableRangesUnixMs: complete ? gaps : null,
    explanation: 'Coverage describes uploaded calibration samples at export time. Missing uploads do not prove the Watch was not recording. Delays, sharing being off, retention, or capture gaps can all leave no data.' };
}

export function makeFeedbackExport(feedback, sessions, { delivery = [], exportedAt = Date.now() } = {}) {
  const selected = sessions.filter(session => session.participantID === feedback.participantID);
  return {
    kind: 'ciggy-missed-cigarette-feedback', formatVersion: 1,
    exportedAt: new Date(exportedAt).toISOString(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    feedbackDateEncoding: 'millisecondsSince1970',
    feedback: { ...feedback, observationType: 'tester-reported', countCorrectionApplied: false },
    coverage: coverageEvidence(selected, feedback.start, feedback.end),
    delivery: delivery.filter(item => item.participantID === feedback.participantID),
    motion: makeExport(selected, { fromMs: feedback.start, toMs: feedback.end }),
    interpretation: 'Tester feedback is not an algorithm diagnosis. Raw data and labels are evidence for a later investigation; saving feedback neither changes the cigarette total nor retrains the detector.',
  };
}
