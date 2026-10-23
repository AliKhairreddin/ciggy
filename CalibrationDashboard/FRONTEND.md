# Motion journal frontend

`public/` contains dependency-free browser modules and static assets. The worker serves only that directory. No real recordings or examples are committed with the frontend.

## Reviewing data

Sign in to the private site, create an iPhone pairing code for each participant, and enable motion sharing in each participant's iPhone app. Shared recordings and their labels expire after 14 days. The browser lists recording metadata first, then retrieves full samples only for recordings being inspected or exported. An open page checks for updated metadata once per minute, pausing while hidden or while a label is being edited. Up to five recordings can be compared with the selected recording. A live recording may have gyroscope samples; accelerometer-only history never gains fabricated gyroscope readings.

The initial filter shows the past 48 hours in the browser's timezone. Today/yesterday use local calendar boundaries, including daylight-saving changes. Choose a recording to fit its motion to the chart. Drag a time range or type exact start/end times, choose the observed activity, and save. Labels can be edited or deleted. Participant names can be renamed. Concurrent label edits use the server's label revision; a stale write is rejected instead of replacing another reviewer's labels.

Explicit imports are saved to the private service when signed in. When served by a plain local HTTP server without `/api/session`, imports are stored in IndexedDB in that browser. This local mode is labeled **This browser only**. Server failures and authorization failures do not silently switch to local mode.

## Recording and annotation format

Native files follow `MotionRecording`, format version 1. Numeric dates are Foundation's default JSON date encoding: **seconds since January 1, 2001 UTC**, including fractional seconds. The frontend preserves those raw numeric sensor timestamps during import and export; it converts them to JavaScript milliseconds only for display and time filtering.

Individual native files are limited to 10 MiB and 18,000 samples, matching the app. Imports must have increasing sample timestamps and finite valid vectors. Saved recording IDs deduplicate repeated imports. Local workspaces and individual labeled exports are bounded to one million samples, and labeled backup files are limited to 128 MiB; select one participant or day for larger data sets. The metadata list remains available for longer cloud histories.

Labeled exports have this outer shape:

```json
{
  "kind": "ciggy-labeled-motion",
  "formatVersion": 1,
  "dateEncoding": "secondsSince2001",
  "exportedAt": "ISO-8601 timestamp",
  "sessions": [{
    "id": "workspace recording ID",
    "participant": "chosen alias",
    "recording": { "id": "original recording UUID", "formatVersion": 1, "samples": [] },
    "annotations": [{
      "id": "annotation UUID",
      "recordingID": "original recording UUID",
      "start": 814123456.123456,
      "end": 814123460.234567,
      "label": "smoking",
      "notes": "Optional observation"
    }]
  }]
}
```

Activities are `smoking`, `eating`, `drinking`, `other`, or `unknown`. Export respects the current participant/source/day filters, clips samples and labels to the selected date period, and preserves original sample sources and precision. Activity labels describe observations and are separate from cigarette counts. They do not train a model automatically.

## Checks

Run `node --test tests/data.test.js` from this directory. The tests cover date encoding and precision, format validation, malformed/oversized imports, source fidelity, duplicate IDs, annotation ownership and boundaries, coverage gaps, sliced exports, and labeled round trips. Run `node --check public/app.js` for module syntax. A local browser preview can be served with `python3 -m http.server 8799 --directory public`.
