import { test } from 'node:test';
import assert from 'node:assert/strict';
import { summarizeRecording, mergeCoverage, timelineExtent } from '../public/timeline.js';
const point = (timestamp, x = 0, source = 'recordedAccelerometer') => ({ timestamp, source,
  gravity: { x: 0, y: 0, z: -1 }, userAcceleration: { x, y: 0, z: 0 } });
test('adjacent files form one coverage range; overlapping history does not double-count time', () => {
  const a = summarizeRecording({ samples: [point(0), point(.1), point(.2)] });
  const b = summarizeRecording({ samples: [point(.3), point(.4), point(.5)] });
  assert.deepEqual(mergeCoverage([...a.ranges, ...b.ranges, ...a.ranges]), [[0, .5]]);
  assert.deepEqual(mergeCoverage([...a.ranges, ...b.ranges], .15, .45), [[.15, .45]]);
});
test('gaps and unavailable gyroscope readings stay missing; brief peaks survive summary', () => {
  const result = summarizeRecording({ samples: [point(0), point(.1, 9), point(.2), point(60), point(60.1)] });
  assert.equal(result.bins.length, 2);
  assert.deepEqual(result.bins[0].values.userAcceleration.magnitude, [0, 9]);
  assert.equal(result.bins[0].values.rotationRate, undefined);
  assert.deepEqual(mergeCoverage(result.ranges), [[0, .2], [60, 60.1]]);
});
test('default extent includes all received files instead of only the newest tiny fragment', () => {
  const sessions = [{ overview: summarizeRecording({ samples: [point(0), point(.1)] }) },
    { overview: summarizeRecording({ samples: [point(7200)] }) }];
  const range = timelineExtent(sessions, [0, 1]);
  assert.ok(range[0] < 978307200000);
  assert.ok(range[1] > 978314400000);
  assert.deepEqual(timelineExtent([], [10, 20]), [10, 20]);
});
