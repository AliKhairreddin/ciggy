export function recording(id, firstSample) {
  const start = (Date.parse(firstSample) - Date.UTC(2001, 0, 1)) / 1000;
  return {
    id,
    formatVersion: 1,
    label: "unlabelled",
    startedAt: start,
    samples: Array.from({ length: 15 }, (_, index) => ({
      timestamp: start + index,
      source: "recordedAccelerometer",
      gravity: { x: 0, y: 0, z: -1 },
      userAcceleration: { x: 0, y: 0, z: 0 },
    })),
  };
}
