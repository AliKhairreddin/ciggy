export function deliverySummary(report, now = Date.now()) {
  if (!report) return 'Waiting for a delivery report from an updated iPhone. Existing motion is still shown below.';
  const stale = now - report.observedAt > 90 * 60000;
  if (stale) return 'This report is over 90 minutes old. The devices may have progressed since then.';
  if (report.phonePendingCount > 0) {
    if (report.phoneScheduledCount > 0) return 'Motion is on iPhone and queued with Apple’s background upload service. Wi-Fi and system scheduling can delay delivery.';
    return 'Motion reached iPhone and is waiting for upload preparation or retry.';
  }
  if (report.watch?.checkedAt && now - report.watch.checkedAt > 90 * 60000) return 'iPhone reported no upload backlog. The Watch report is over 90 minutes old, so its current queue is unknown.';
  if (report.watch?.queuedTransferCount > 0) return 'Watch last reported saved motion waiting for transfer to iPhone.';
  if (report.watch?.pendingWindowCount > 0) return 'Watch last reported motion history still awaiting preparation.';
  return 'No backlog was reported at this check. This does not prove uninterrupted capture.';
}
