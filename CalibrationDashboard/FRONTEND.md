# Motion journal frontend

`src/` contains the React interface, with shadcn/ui components, Tailwind CSS, and a monochrome light theme. `components.json` configures the neutral shadcn registry. Shared recording validation, IndexedDB storage, and measured timeline summaries remain in `public/`; Vite imports those modules without copying the directory. The Worker serves only the production `dist/` build, behind the existing authentication gate. No real recordings or examples are committed with the frontend.

## Reviewing data

Sign in to the private site, create an iPhone pairing code for each participant, and enable motion sharing in each participant's iPhone app. Shared recordings and their labels expire after 14 days. The browser lists recording metadata and saved five-second summaries for the selected period; raw samples are retrieved only when saving or deleting a label, or exporting. All received files in the period appear together. An open page checks metadata once per minute, pausing while hidden, editing a label, or using a dialog. It reuses unchanged summaries and reads the newest metadata page between full reconciliations every five minutes. Failed or incomplete responses preserve the previous view. Participant and recording-type filters reuse loaded metadata. Accelerometer-only history never gains fabricated gyroscope readings.

The visible period picker starts at the past 48 hours and offers quick presets, a chosen day, and a custom start/end date and time. Custom dates apply together after validation. Today/yesterday use local calendar boundaries, including daylight-saving changes. The chart uses the applied period exactly; zoom and fit stay inside it. Counters, recordings, labels, and exports follow that period. Empty periods stay visibly empty. Missing summaries make coverage and label totals explicitly partial.

Choose a source recording to fit its motion to the chart. Drag a measured time range or type exact activity start/end times, choose the observed activity, and save. Activity times are separate from the period filter. Labels can be edited or deleted; participant names can be renamed. Concurrent label edits use the server's label revision; stale writes are rejected. The Delivery tab contains device queues and timing details. Import, pairing, rename, and deletion use accessible shadcn dialogs; per-response style nonces allow their scroll-lock styles under the strict content security policy.

Explicit imports are saved to the private service when signed in. In a browser-only local preview without `/api/session`, imports are stored in IndexedDB and labeled **This browser only**. Server and authorization failures do not silently switch to local mode.

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

Run `npm test`, `npm run typecheck`, and `npx wrangler deploy --dry-run` from this directory. Checks cover date encoding, validation, source fidelity, labels, exports, exact custom ranges, DST, incomplete refreshes, cache reuse, and private APIs. `npm run build` bundles the frontend; Wrangler runs it automatically before deployment. `npm run dev:ui` starts a browser-only Vite preview; `npm run dev` runs the full Worker. A production browser-only preview can be served with `python3 -m http.server 8799 --directory dist` after building. Use synthetic files for browser checks; keep screenshots and real tester evidence out of this public repository.
