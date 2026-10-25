import {
  useEffect,
  useMemo,
  useRef,
  useState,
  useSyncExternalStore,
} from "react";
import {
  Activity,
  ArrowDownToLine,
  CalendarDays,
  Check,
  ChevronDown,
  Cigarette,
  Clock3,
  FileAudio,
  Focus,
  LockKeyhole,
  Minus,
  Pencil,
  Plus,
  RefreshCw,
  Smartphone,
  Tags,
  Trash2,
  Users,
  Watch,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { NativeSelect } from "@/components/ui/native-select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";
import { api, createJournal } from "@/lib/journal";
import {
  constrainView,
  filterSessions,
  periodBounds,
  recordingBounds,
  recordingSources,
  timeInput,
} from "@/lib/period";
import { MotionChart } from "@/components/motion-chart";
import {
  appleSecondsToMs,
  msToAppleSeconds,
  cleanAlias,
  parseImport,
  validateAnnotation,
  makeExport,
  LIMITS,
} from "../public/data.js";
import { mergeCoverage } from "../public/timeline.js";
import { deliverySummary } from "../public/delivery.js";

const journal = createJournal();
const dateTime = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
});
const shortTime = new Intl.DateTimeFormat(undefined, {
  hour: "numeric",
  minute: "2-digit",
});
const sourceName = (source) =>
  source === "recordedAccelerometer" ? "Background history" : "Live motion";
const activities = {
  smoking: "Smoking",
  eating: "Eating",
  drinking: "Drinking",
  other: "Something else",
  unknown: "Not sure",
};
const duration = (milliseconds) => {
  if (milliseconds > 0 && milliseconds < 1000) return "<1s";
  const minutes = milliseconds / 60000;
  return minutes < 1
    ? `${Math.round(milliseconds / 1000)}s`
    : minutes < 60
      ? `${Math.round(minutes)}m`
      : `${(minutes / 60).toFixed(1)}h`;
};
const coverageFor = (sessions, range, source) =>
  [
    ...Map.groupBy(
      sessions,
      (session) => session.participantID ?? session.participant,
    ).values(),
  ].reduce(
    (total, group) =>
      total +
      mergeCoverage(
        group.flatMap((session) =>
          session.overview.ranges.filter(
            (row) => !source || row.source === source,
          ),
        ),
        msToAppleSeconds(range[0]),
        msToAppleSeconds(range[1]),
      ).reduce((sum, [start, end]) => sum + (end - start) * 1000, 0),
    0,
  );

function Field({ label, id, children, className }) {
  return (
    <div className={cn("min-w-0 space-y-2", className)}>
      <Label htmlFor={id} className="text-xs font-medium text-muted-foreground">
        {label}
      </Label>
      {children}
    </div>
  );
}
function Empty({ icon: Icon = Activity, title, children }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-12 text-center">
      <div className="mb-4 rounded-xl border bg-muted/50 p-3">
        <Icon className="size-5" />
      </div>
      <h3 className="font-medium">{title}</h3>
      <p className="mt-2 max-w-sm text-sm leading-6 text-muted-foreground">
        {children}
      </p>
    </div>
  );
}

function PeriodPicker({ state, disabled, onApply }) {
  const [draft, setDraft] = useState(state.filters),
    [error, setError] = useState("");
  useEffect(() => {
    setDraft(state.filters);
    setError("");
  }, [state.filters]);
  function changePeriod(period) {
    const next = { ...draft, period };
    if (period === "custom" && (!next.start || !next.end)) {
      next.start = timeInput(state.range[0]);
      next.end = timeInput(state.range[1]);
    }
    setDraft(next);
    setError("");
    if (!["custom", "day"].includes(period))
      void onApply(next).then((ok) => {
        if (!ok) setDraft(state.filters);
      });
  }
  async function submit(event) {
    event.preventDefault();
    try {
      periodBounds(draft, {
        connected: state.mode === "connected",
        sessions: state.sessions,
      });
      setError("");
      if (!(await onApply(draft))) setDraft(state.filters);
    } catch (cause) {
      setError(cause.message);
    }
  }
  return (
    <form onSubmit={submit} className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="mr-2 flex items-center gap-2 text-sm font-medium">
          <CalendarDays className="size-4" />
          Period
        </div>
        {[
          ["today", "Today"],
          ["yesterday", "Yesterday"],
          ["48h", "Past 48 hours"],
          ["7d", "7 days"],
          ["custom", "Custom"],
        ].map(([value, label]) => (
          <Button
            key={value}
            type="button"
            size="sm"
            variant={draft.period === value ? "default" : "ghost"}
            aria-pressed={draft.period === value}
            disabled={disabled}
            onClick={() => changePeriod(value)}
          >
            {label}
          </Button>
        ))}
        <div className="ml-auto min-w-36">
          <NativeSelect
            aria-label="Time period"
            value={draft.period}
            disabled={disabled}
            onChange={(event) => changePeriod(event.target.value)}
          >
            <option value="1h">Past hour</option>
            <option value="today">Today</option>
            <option value="yesterday">Yesterday</option>
            <option value="24h">Past 24 hours</option>
            <option value="48h">Past 48 hours</option>
            <option value="7d">Past 7 days</option>
            <option value="day">Choose a day</option>
            <option value="custom">Custom range</option>
            <option value="all">
              {state.mode === "connected"
                ? "Past 14 days"
                : "All imported data"}
            </option>
          </NativeSelect>
        </div>
      </div>
      {["day", "custom"].includes(draft.period) && (
        <div className="grid items-end gap-3 rounded-lg border bg-muted/30 p-4 sm:grid-cols-[1fr_1fr_auto]">
          {draft.period === "day" ? (
            <Field label="Day" id="period-day">
              <Input
                id="period-day"
                type="date"
                required
                value={draft.day}
                disabled={disabled}
                onChange={(event) =>
                  setDraft({ ...draft, day: event.target.value })
                }
              />
            </Field>
          ) : (
            <>
              <Field label="Start date & time" id="period-start">
                <Input
                  id="period-start"
                  type="datetime-local"
                  step="0.001"
                  required
                  value={draft.start}
                  disabled={disabled}
                  onChange={(event) =>
                    setDraft({ ...draft, start: event.target.value })
                  }
                />
              </Field>
              <Field label="End date & time" id="period-end">
                <Input
                  id="period-end"
                  type="datetime-local"
                  step="0.001"
                  required
                  value={draft.end}
                  disabled={disabled}
                  onChange={(event) =>
                    setDraft({ ...draft, end: event.target.value })
                  }
                />
              </Field>
            </>
          )}
          <Button type="submit" disabled={disabled}>
            Apply period
          </Button>
          <p className="text-xs text-muted-foreground sm:col-span-full">
            Times use your local timezone. Apply to update the chart,
            recordings, labels, and export.
          </p>
          {error && (
            <p role="alert" className="text-sm font-medium sm:col-span-full">
              {error}
            </p>
          )}
        </div>
      )}
    </form>
  );
}

function Delivery({ state }) {
  const at = (value) =>
    value == null ? "Not reported" : dateTime.format(value);
  return (
    <Card className="gap-0 shadow-none">
      <CardHeader className="pb-5">
        <CardTitle className="flex items-center gap-2 text-base">
          <Watch className="size-4" />
          From Watch to workspace
        </CardTitle>
        <CardDescription>
          Last reported delivery state. Background scheduling can delay these
          reports.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {state.deliveryError && (
          <p role="status" className="mb-4 rounded-lg border p-3 text-sm">
            Delivery status could not refresh. The last report and saved motion
            are kept.
          </p>
        )}
        {!state.delivery.length ? (
          <Empty icon={Smartphone} title="No delivery reports yet">
            {state.mode === "connected"
              ? "Reports appear when a connected iPhone shares its delivery status."
              : "Connect to the private workspace to view device delivery."}
          </Empty>
        ) : (
          state.delivery.map(
            ({ participantID, participant, report, receivedAt }, index) => (
              <details
                key={participantID ?? index}
                className="group border-t py-4"
              >
                <summary className="flex list-none items-center gap-3">
                  <span className="rounded-lg bg-muted p-2">
                    <Smartphone className="size-4" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm font-medium">
                      {participant}
                    </span>
                    <span className="mt-1 block text-xs leading-5 text-muted-foreground">
                      {deliverySummary(report)}
                    </span>
                  </span>
                  <ChevronDown className="size-4 shrink-0 transition-transform group-open:rotate-180" />
                </summary>
                {report && (
                  <div className="mt-4 grid gap-4 rounded-lg bg-muted/50 p-4 text-xs sm:grid-cols-2">
                    <div>
                      <p className="font-medium">iPhone → workspace</p>
                      <p className="mt-2 leading-6 text-muted-foreground">
                        Checked {at(report.observedAt)}
                        <br />
                        Received {at(receivedAt)}
                        <br />
                        Last motion upload {at(report.phoneLastUploadedAt)}
                        <br />
                        {report.phonePendingCount} files waiting ·{" "}
                        {report.phoneScheduledCount} scheduled
                        <br />
                        iPhone build {report.phoneBuild ?? "Unknown"}
                      </p>
                    </div>
                    <div>
                      <p className="font-medium">Watch → iPhone</p>
                      <p className="mt-2 leading-6 text-muted-foreground">
                        Last received {at(report.phoneLastReceivedAt)}
                        <br />
                        {report.watch ? (
                          <>
                            Checked {at(report.watch.checkedAt)}
                            <br />
                            {report.watch.queuedTransferCount} files waiting ·{" "}
                            {report.watch.pendingWindowCount} windows pending
                            <br />
                            Last batch {at(report.watch.lastBatchAt)}
                            <br />
                            Next eligible batch {at(report.watch.nextBatchAt)}
                            <br />
                            Last transfer {at(report.watch.lastDeliveredAt)}
                            <br />
                            Watch build {report.watch.build ?? "Unknown"}
                          </>
                        ) : (
                          "No Watch report yet"
                        )}
                      </p>
                    </div>
                  </div>
                )}
              </details>
            ),
          )
        )}
      </CardContent>
    </Card>
  );
}

export function App() {
  const state = useSyncExternalStore(journal.subscribe, journal.getSnapshot);
  const [view, setView] = useState(null),
    [signal, setSignal] = useState("userAcceleration"),
    [axis, setAxis] = useState("magnitude");
  const [active, setActive] = useState(""),
    [form, setForm] = useState({
      start: "",
      end: "",
      activity: "smoking",
      notes: "",
      editing: null,
    }),
    [dirty, setDirty] = useState(false);
  const [tab, setTab] = useState("labels"),
    [modal, setModal] = useState(null),
    [alias, setAlias] = useState(""),
    [pairing, setPairing] = useState(null),
    [modalError, setModalError] = useState(""),
    [working, setWorking] = useState(false);
  const fileInput = useRef(null),
    formRef = useRef(null),
    paused = useRef(false);
  const connected = state.mode === "connected",
    disabled =
      state.busy ||
      working ||
      state.mode === "loading" ||
      state.mode === "error";
  const visible = useMemo(
    () => filterSessions(state.sessions, state.filters, state.range),
    [state.sessions, state.filters, state.range],
  );
  const ready = useMemo(
    () =>
      visible.map((session) => state.overviews.get(session.id)).filter(Boolean),
    [visible, state.overviews],
  );
  const participants = useMemo(
    () => [
      ...new Map(
        state.sessions.map((session) => [
          session.participantID ?? session.participant,
          session.participant,
        ]),
      ),
    ],
    [state.sessions],
  );
  const chartRange = view ?? state.range;
  const labels = useMemo(
    () =>
      ready
        .flatMap((session) =>
          (session.annotations ?? [])
            .filter(
              (annotation) =>
                appleSecondsToMs(annotation.end) >= state.range[0] &&
                appleSecondsToMs(annotation.start) <= state.range[1],
            )
            .map((annotation) => ({ annotation, session })),
        )
        .sort((a, b) => b.annotation.start - a.annotation.start),
    [ready, state.range],
  );
  const missing = visible.length - ready.length;
  const coverage = coverageFor(ready, state.range, state.filters.source);
  const activeSession = visible.find((session) => session.id === active);
  const selection =
    dirty &&
    form.start &&
    form.end &&
    Number.isFinite(new Date(form.start).getTime()) &&
    Number.isFinite(new Date(form.end).getTime())
      ? [new Date(form.start).getTime(), new Date(form.end).getTime()]
      : null;
  const latest = visible.length
    ? Math.max(...visible.map((session) => recordingBounds(session)[1]))
    : null;
  paused.current = dirty || Boolean(modal) || working;
  useEffect(() => {
    void journal.initialize();
  }, []);
  useEffect(() => {
    const timer = setInterval(() => {
      if (
        journal.getSnapshot().mode === "connected" &&
        !document.hidden &&
        !paused.current
      )
        void journal.refresh(undefined, { incremental: true });
    }, 60000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    setView(null);
    // A file can overlap both periods. Keep an untouched activity range inside
    // the newly applied period even when the selected file itself stays the same.
    if (!dirty && activeSession) selectRecording(activeSession);
  }, [state.filters]);
  useEffect(() => {
    if (!dirty && (!activeSession || !active)) {
      if (visible.length) selectRecording(visible[0]);
      else {
        setActive("");
        setForm({
          start: "",
          end: "",
          activity: "smoking",
          notes: "",
          editing: null,
        });
      }
    }
  }, [visible, active, activeSession, dirty]);
  useEffect(() => {
    if (!dirty && activeSession)
      setForm((previous) => ({
        ...previous,
        revision: activeSession.labelRevision,
      }));
  }, [activeSession?.labelRevision, active, dirty]);

  function report(error) {
    journal.notice(error.message, true);
  }
  function guardDraft() {
    if (!dirty) return true;
    journal.notice(
      "Save or reset your activity label before changing the view.",
      true,
    );
    return false;
  }
  function selectRecording(session, fit = false) {
    const range = recordingBounds(session);
    setActive(session.id);
    setDirty(false);
    setForm({
      start: timeInput(Math.max(range[0], state.range[0])),
      end: timeInput(Math.min(range[1], state.range[1])),
      activity: "smoking",
      notes: "",
      editing: null,
      revision: session.labelRevision,
    });
    if (fit)
      setView(constrainView([range[0] - 1000, range[1] + 1000], state.range));
  }
  async function applyFilters(filters) {
    if (!guardDraft()) return false;
    journal.notice(null);
    if (
      filters.period === state.filters.period &&
      filters.start === state.filters.start &&
      filters.end === state.filters.end &&
      filters.day === state.filters.day
    ) {
      // Participant/source changes filter saved metadata without another source pull.
      return journal.refresh(filters, { localFilter: true });
    } else return journal.refresh(filters);
  }
  function zoom(factor) {
    const center = (chartRange[0] + chartRange[1]) / 2,
      span = Math.max(1000, (chartRange[1] - chartRange[0]) * factor);
    setView(constrainView([center - span / 2, center + span / 2], state.range));
  }
  function markRange(range) {
    if (!guardDraft()) return;
    const options = ready
      .map((session) => ({
        session,
        overlap: mergeCoverage(
          session.overview.ranges.filter(
            (row) =>
              !state.filters.source || row.source === state.filters.source,
          ),
          msToAppleSeconds(range[0]),
          msToAppleSeconds(range[1]),
        ).reduce((sum, [start, end]) => sum + end - start, 0),
      }))
      .filter((item) => item.overlap > 0)
      .sort((a, b) => b.overlap - a.overlap);
    if (!options.length) {
      journal.notice(
        "There are no measured samples in that moment. Choose a recorded section.",
        true,
      );
      return;
    }
    const session = options[0].session,
      bounds = recordingBounds(session);
    setActive(session.id);
    setDirty(true);
    setForm({
      start: timeInput(Math.max(bounds[0], range[0])),
      end: timeInput(Math.min(bounds[1], range[1])),
      activity: "smoking",
      notes: "",
      editing: null,
      revision: session.labelRevision,
    });
    if (range[0] < bounds[0] || range[1] > bounds[1])
      journal.notice(
        "Selected the matching recording. Labels are limited to one file; label adjacent files separately.",
      );
    formRef.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }
  async function saveLabel(event) {
    event.preventDefault();
    setWorking(true);
    try {
      const session = await journal.getSession(active),
        samples = session.recording.samples;
      if (form.revision !== session.labelRevision)
        throw new Error(
          "This recording changed. Reset your draft, refresh, and review its labels before saving.",
        );
      let start = msToAppleSeconds(new Date(form.start).getTime()),
        end = msToAppleSeconds(new Date(form.end).getTime());
      if (Math.abs(start - samples[0].timestamp) < 0.001)
        start = samples[0].timestamp;
      if (Math.abs(end - samples.at(-1).timestamp) < 0.001)
        end = samples.at(-1).timestamp;
      const annotation = validateAnnotation(
        {
          id: form.editing ?? crypto.randomUUID(),
          recordingID: session.recording.id,
          start,
          end,
          label: form.activity,
          notes: form.notes,
        },
        session.recording,
      );
      await journal.persistLabels(session, [
        ...session.annotations.filter((item) => item.id !== annotation.id),
        annotation,
      ]);
      setDirty(false);
      setForm({
        ...form,
        notes: "",
        editing: null,
        revision: journal
          .getSnapshot()
          .sessions.find((item) => item.id === active)?.labelRevision,
      });
      journal.notice("Activity label saved.");
    } catch (error) {
      report(error);
    } finally {
      setWorking(false);
    }
  }
  async function editLabel(session, annotation) {
    if (!guardDraft()) return;
    setActive(session.id);
    setDirty(true);
    setForm({
      start: timeInput(appleSecondsToMs(annotation.start)),
      end: timeInput(appleSecondsToMs(annotation.end)),
      activity: annotation.label,
      notes: annotation.notes,
      editing: annotation.id,
      revision: session.labelRevision,
    });
    setView(
      constrainView(
        [
          appleSecondsToMs(annotation.start) - 60000,
          appleSecondsToMs(annotation.end) + 60000,
        ],
        state.range,
      ),
    );
    formRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
  }
  function openModal(value) {
    setModalError("");
    setAlias(value?.session?.participant ?? "");
    setPairing(null);
    setModal(value);
  }
  async function handleModal(event) {
    event.preventDefault();
    setWorking(true);
    setModalError("");
    try {
      if (modal.type === "pair") {
        setPairing(
          await api("/api/pairing", {
            method: "POST",
            body: JSON.stringify({ alias: cleanAlias(alias) }),
          }),
        );
        return;
      }
      if (modal.type === "import") {
        const participant = cleanAlias(alias),
          incoming = [];
        for (const file of modal.files) {
          if (file.size > LIMITS.datasetBytes)
            throw new Error(`${file.name} is larger than 128 MB.`);
          incoming.push(
            ...parseImport(await file.text(), file.name, participant),
          );
        }
        journal.notice(await journal.importSessions(incoming));
      }
      if (modal.type === "rename") await journal.rename(modal.session, alias);
      if (modal.type === "remove") await journal.remove(modal.session);
      if (modal.type === "deleteLabel") {
        const session = await journal.getSession(modal.session.id);
        if (session.labelRevision !== modal.session.labelRevision)
          throw new Error(
            "This recording changed. Refresh and review its labels before deleting.",
          );
        await journal.persistLabels(
          session,
          session.annotations.filter(
            (annotation) => annotation.id !== modal.annotation.id,
          ),
        );
        journal.notice("Activity label deleted.");
      }
      setModal(null);
    } catch (error) {
      setModalError(error.message);
    } finally {
      setWorking(false);
    }
  }
  async function exportData() {
    setWorking(true);
    try {
      const selected = [];
      let total = 0;
      for (const metadata of visible) {
        const session = await journal.getSession(metadata.id);
        total += session.recording.samples.length;
        if (total > LIMITS.totalSamples)
          throw new Error(
            "This selection is too large for one export. Choose a shorter period or one participant.",
          );
        selected.push(session);
      }
      const data = makeExport(selected, {
        fromMs: state.range[0],
        toMs: state.range[1],
        source: state.filters.source,
      });
      const blob = new Blob([JSON.stringify(data)], {
        type: "application/json",
      });
      if (blob.size > LIMITS.datasetBytes)
        throw new Error(
          "This export is larger than 128 MB. Choose a shorter period.",
        );
      const url = URL.createObjectURL(blob),
        anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `ciggy-labeled-motion-${new Date().toISOString().slice(0, 10)}.json`;
      anchor.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      journal.notice(
        `${data.sessions.length} recordings exported for the selected period.`,
      );
    } catch (error) {
      report(error);
    } finally {
      setWorking(false);
    }
  }
  const updateForm = (field, value) => {
    setForm({ ...form, [field]: value });
    setDirty(true);
  };
  const stats = [
    {
      title: "Recordings",
      value: visible.length.toLocaleString(),
      hint: "Files in this period",
      icon: FileAudio,
    },
    {
      title: "Recorded time",
      value: missing ? `${duration(coverage)}+` : duration(coverage),
      hint: missing
        ? "Partial · chart data still missing"
        : "Excludes gaps and overlaps",
      icon: Clock3,
    },
    {
      title: "Participants",
      value: new Set(
        visible.map((session) => session.participantID ?? session.participant),
      ).size,
      hint: "Sharing in this period",
      icon: Users,
    },
    {
      title: "Activity labels",
      value: `${labels.length}${missing ? "+" : ""}`,
      hint: missing
        ? "Partial · chart data still missing"
        : "Your observations",
      icon: Tags,
    },
  ];

  return (
    <div className="min-h-screen">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-[1480px] flex-wrap items-center justify-between gap-4 px-5 py-4 sm:px-8 lg:px-10">
          <a
            href="#timeline"
            className="flex items-center gap-3"
            aria-label="Ciggy motion journal"
          >
            <span className="flex size-9 items-center justify-center rounded-xl bg-black text-white">
              <Cigarette className="size-5 -rotate-12" />
            </span>
            <span className="text-xl font-extrabold tracking-[-.06em]">
              ciggy<span className="font-normal">.</span>
            </span>
            <span className="mx-1 hidden text-xl font-light text-neutral-300 sm:inline">
              /
            </span>
            <span className="hidden text-sm text-muted-foreground sm:inline">
              Motion journal
            </span>
          </a>
          <div className="flex items-center gap-2">
            <Badge
              variant="outline"
              className="hidden gap-1.5 rounded-full px-2.5 py-1 sm:flex"
            >
              <LockKeyhole className="size-3" />
              {connected
                ? "Private workspace"
                : state.mode === "local"
                  ? "This browser only"
                  : state.mode === "error"
                    ? "Connection needed"
                    : "Connecting"}
            </Badge>
            {connected && (
              <Button
                variant="ghost"
                size="sm"
                disabled={disabled || dirty}
                onClick={() => openModal({ type: "pair" })}
              >
                <Smartphone />
                Connect iPhone
              </Button>
            )}
            <Button
              size="sm"
              disabled={disabled || dirty}
              onClick={() => fileInput.current.click()}
            >
              <Plus />
              Import recordings
            </Button>
            <input
              ref={fileInput}
              type="file"
              accept=".json,application/json"
              multiple
              hidden
              onChange={(event) => {
                const files = [...event.target.files];
                event.target.value = "";
                if (files.length) openModal({ type: "import", files });
              }}
            />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[1480px] space-y-6 px-5 py-8 sm:px-8 lg:px-10 lg:py-10">
        <section
          id="timeline"
          className="flex flex-wrap items-end justify-between gap-4"
        >
          <div>
            <div className="mb-2 flex items-center gap-2 text-xs font-medium text-muted-foreground">
              <span className="size-1.5 rounded-full bg-black" />
              THE MOTION JOURNAL
            </div>
            <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
              A little wrist perspective.
            </h1>
            <p className="mt-3 text-sm text-muted-foreground">
              Your recorded motion, with the moments that give it meaning.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="outline"
              disabled={disabled || dirty}
              onClick={() =>
                void journal.refresh().then((ok) => {
                  if (ok) journal.notice("Recordings refreshed.");
                })
              }
            >
              <RefreshCw className={state.busy ? "animate-spin" : ""} />
              Refresh
            </Button>
            <Button
              variant="outline"
              disabled={disabled || !visible.length}
              onClick={exportData}
            >
              <ArrowDownToLine />
              Export data
            </Button>
          </div>
        </section>

        {state.notice && (
          <div
            role={state.notice.error ? "alert" : "status"}
            className={cn(
              "flex items-start gap-3 rounded-xl border bg-white px-4 py-3 text-sm",
              state.notice.error && "border-neutral-500",
            )}
          >
            <span className="mt-0.5 shrink-0">
              {state.notice.error ? (
                <Activity className="size-4" />
              ) : (
                <Check className="size-4" />
              )}
            </span>
            <p className="min-w-0 flex-1">{state.notice.message}</p>
            <Button
              variant="ghost"
              size="icon-xs"
              aria-label="Dismiss message"
              onClick={() => journal.notice(null)}
            >
              <X />
            </Button>
          </div>
        )}

        <Card className="gap-0 py-4 shadow-none">
          <CardContent className="space-y-4 px-4 sm:px-5">
            <PeriodPicker
              state={state}
              disabled={disabled || dirty}
              onApply={applyFilters}
            />
            <Separator />
            <div className="flex flex-wrap items-center gap-3">
              <div className="w-full sm:w-48">
                <NativeSelect
                  aria-label="Participant"
                  value={state.filters.participant}
                  disabled={disabled || dirty}
                  onChange={(event) =>
                    void applyFilters({
                      ...state.filters,
                      participant: event.target.value,
                    })
                  }
                >
                  <option value="">All participants</option>
                  {participants.map(([id, name]) => (
                    <option value={id} key={id}>
                      {name}
                    </option>
                  ))}
                </NativeSelect>
              </div>
              <div className="w-full sm:w-48">
                <NativeSelect
                  aria-label="Recording type"
                  value={state.filters.source}
                  disabled={disabled || dirty}
                  onChange={(event) =>
                    void applyFilters({
                      ...state.filters,
                      source: event.target.value,
                    })
                  }
                >
                  <option value="">All recording types</option>
                  <option value="recordedAccelerometer">
                    Background history
                  </option>
                  <option value="liveDeviceMotion">Live motion</option>
                </NativeSelect>
              </div>
              <p
                className="ml-auto text-xs text-muted-foreground"
                aria-live="polite"
              >
                {state.busy
                  ? "Loading period…"
                  : `${dateTime.format(state.range[0])} — ${dateTime.format(state.range[1])}`}
                <span className="ml-2 text-neutral-400">Local time</span>
              </p>
            </div>
          </CardContent>
        </Card>

        <section
          className="grid grid-cols-2 gap-3 lg:grid-cols-4"
          aria-label="Selected period overview"
        >
          {stats.map(({ title, value, hint, icon: Icon }) => (
            <Card key={title} className="gap-3 py-4 shadow-none">
              <CardContent className="px-4 sm:px-5">
                <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
                  <span>{title}</span>
                  <Icon className="size-4" />
                </div>
                <div className="tabular mt-3 text-3xl font-semibold tracking-tight">
                  {state.updatedAt ? value : "—"}
                </div>
                <p className="mt-2 text-[11px] text-muted-foreground">
                  {state.updatedAt ? hint : "Waiting for workspace data"}
                </p>
              </CardContent>
            </Card>
          ))}
        </section>

        <Card className="gap-0 overflow-hidden pb-0 shadow-none">
          <CardHeader className="gap-4 px-4 pb-5 sm:px-6">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <CardTitle className="text-base">Motion overview</CardTitle>
                <CardDescription className="mt-2 text-xs">
                  {latest
                    ? `Latest file ends ${dateTime.format(latest)} · ${duration(Math.max(0, Date.now() - latest))} ago`
                    : state.mode === "loading"
                      ? "Opening your workspace…"
                      : "No motion in the selected period"}
                </CardDescription>
              </div>
              <Badge variant="secondary" className="rounded-full font-normal">
                {state.hydrating
                  ? `Loading ${ready.length}/${visible.length}`
                  : `${visible.length} recordings`}
              </Badge>
            </div>
            <div className="flex flex-wrap items-end justify-between gap-3">
              <div className="flex min-w-0 flex-wrap gap-2">
                <div className="w-44">
                  <NativeSelect
                    aria-label="Signal"
                    value={signal}
                    onChange={(event) => setSignal(event.target.value)}
                  >
                    <option value="userAcceleration">Movement · g</option>
                    <option value="gravity">Orientation · g</option>
                    <option value="rotationRate">Rotation · rad/s</option>
                  </NativeSelect>
                </div>
                <div className="w-28">
                  <NativeSelect
                    aria-label="Axis"
                    value={axis}
                    onChange={(event) => setAxis(event.target.value)}
                  >
                    <option value="magnitude">Magnitude</option>
                    <option value="x">X axis</option>
                    <option value="y">Y axis</option>
                    <option value="z">Z axis</option>
                  </NativeSelect>
                </div>
              </div>
              <div className="flex items-center gap-1">
                <Button variant="ghost" size="sm" onClick={() => setView(null)}>
                  Reset zoom
                </Button>
                <Button
                  variant="outline"
                  size="icon-sm"
                  aria-label="Zoom out"
                  onClick={() => zoom(2)}
                >
                  <Minus />
                </Button>
                <Button
                  variant="outline"
                  size="icon-sm"
                  aria-label="Zoom in"
                  onClick={() => zoom(0.5)}
                >
                  <Plus />
                </Button>
                <Button
                  variant="outline"
                  size="icon-sm"
                  aria-label="Fit selected recording"
                  disabled={!activeSession}
                  onClick={() => {
                    const bounds = recordingBounds(activeSession);
                    setView(
                      constrainView(
                        [bounds[0] - 1000, bounds[1] + 1000],
                        state.range,
                      ),
                    );
                  }}
                >
                  <Focus />
                </Button>
              </div>
            </div>
          </CardHeader>
          <div className="px-2 sm:px-4">
            <MotionChart
              sessions={ready}
              range={chartRange}
              signal={signal}
              axis={axis}
              source={state.filters.source}
              selection={selection}
              loading={state.hydrating || state.mode === "loading"}
              failed={state.failures.size > 0}
              onSelect={markRange}
            />
          </div>
          {ready.length > 0 && (
            <div className="flex flex-wrap gap-x-5 gap-y-2 px-6 pb-4 text-xs">
              {[
                ...Map.groupBy(
                  ready,
                  (session) => session.participantID ?? session.participant,
                ),
              ].map(([id, group], index) => (
                <span key={id} className="flex items-center gap-2">
                  <span
                    className={cn(
                      "size-2 rounded-full",
                      [
                        "bg-neutral-900",
                        "bg-neutral-500",
                        "bg-neutral-700",
                        "bg-neutral-400",
                      ][index % 4],
                    )}
                  />
                  <span>{group[0].participant}</span>
                  <span className="text-muted-foreground">
                    {duration(
                      coverageFor(group, chartRange, state.filters.source),
                    )}{" "}
                    recorded
                  </span>
                </span>
              ))}
            </div>
          )}
          <div className="flex flex-wrap items-center justify-between gap-3 border-t bg-muted/25 px-5 py-3 text-[11px] text-muted-foreground">
            <div className="flex flex-wrap gap-4">
              <span className="flex items-center gap-2">
                <span className="w-5 border-t border-neutral-800" />
                Background history
              </span>
              <span className="flex items-center gap-2">
                <span className="w-5 border-t border-dashed border-neutral-500" />
                Live motion
              </span>
            </div>
            <span className="tabular">
              {dateTime.format(chartRange[0])} —{" "}
              {dateTime.format(chartRange[1])}
            </span>
          </div>
        </Card>
        <div className="-mt-2 flex flex-wrap items-center justify-between gap-2 px-1 text-xs text-muted-foreground">
          <p>
            {missing
              ? `${ready.length}/${visible.length} recordings loaded${state.failures.size ? " · Some chart data failed. Refresh to retry." : ""}. `
              : ""}
            Five-second measured ranges. Gaps have no samples; peaks are not
            cigarette detections.
          </p>
          <span>
            {connected
              ? "Uploads arrive in batches"
              : "Imports stay in this browser"}
          </span>
        </div>

        <div className="grid grid-cols-1 items-start gap-6 xl:grid-cols-[minmax(0,1fr)_380px]">
          <section className="min-w-0" aria-label="Workspace details">
            <Tabs value={tab} onValueChange={setTab}>
              <TabsList className="mb-3 grid w-full grid-cols-3 sm:inline-flex sm:w-fit">
                <TabsTrigger
                  value="labels"
                  className="px-2 text-xs sm:px-3 sm:text-sm"
                >
                  <Tags className="hidden sm:block" />
                  <span className="sm:hidden">Labels</span>
                  <span className="hidden sm:inline">Activity labels</span>
                  <Badge
                    variant="secondary"
                    className="ml-1 px-1.5 text-[10px]"
                  >
                    {labels.length}
                  </Badge>
                </TabsTrigger>
                <TabsTrigger
                  value="recordings"
                  className="px-2 text-xs sm:px-3 sm:text-sm"
                >
                  <FileAudio className="hidden sm:block" />
                  Recordings
                </TabsTrigger>
                <TabsTrigger
                  value="delivery"
                  className="px-2 text-xs sm:px-3 sm:text-sm"
                >
                  <Watch className="hidden sm:block" />
                  Delivery
                </TabsTrigger>
              </TabsList>
              <TabsContent value="labels">
                <Card className="gap-0 shadow-none">
                  <CardHeader className="pb-4">
                    <CardTitle className="text-base">
                      Moments with context
                    </CardTitle>
                    <CardDescription>
                      Your observations within the selected period.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    {!labels.length ? (
                      <Empty
                        icon={Tags}
                        title={
                          missing
                            ? "Labels are still loading"
                            : "The human part goes here."
                        }
                      >
                        {missing
                          ? "Some recording summaries are not available yet."
                          : "Select a moment on the timeline, then add what was happening."}
                      </Empty>
                    ) : (
                      <div className="max-h-[480px] overflow-y-auto">
                        {labels.map(({ annotation, session }) => (
                          <div
                            key={`${session.id}:${annotation.id}`}
                            className="flex items-start gap-3 border-t py-4"
                          >
                            <div className="mt-0.5 rounded-lg bg-muted p-2">
                              {annotation.label === "smoking" ? (
                                <Cigarette className="size-4" />
                              ) : (
                                <Tags className="size-4" />
                              )}
                            </div>
                            <div className="min-w-0 flex-1">
                              <p className="text-sm font-medium">
                                {activities[annotation.label]}
                                <span className="ml-2 text-xs font-normal text-muted-foreground">
                                  {session.participant}
                                </span>
                              </p>
                              <p className="mt-1 text-xs text-muted-foreground">
                                {dateTime.format(
                                  appleSecondsToMs(annotation.start),
                                )}{" "}
                                —{" "}
                                {shortTime.format(
                                  appleSecondsToMs(annotation.end),
                                )}
                              </p>
                              {annotation.notes && (
                                <p className="mt-2 whitespace-pre-wrap break-words text-sm text-muted-foreground">
                                  {annotation.notes}
                                </p>
                              )}
                            </div>
                            <div className="flex">
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Edit activity label"
                                disabled={disabled || dirty}
                                onClick={() =>
                                  void editLabel(session, annotation)
                                }
                              >
                                <Pencil />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Delete activity label"
                                disabled={disabled || dirty}
                                onClick={() =>
                                  openModal({
                                    type: "deleteLabel",
                                    session,
                                    annotation,
                                  })
                                }
                              >
                                <Trash2 />
                              </Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
              <TabsContent value="recordings">
                <Card className="gap-0 shadow-none">
                  <CardHeader className="pb-4">
                    <CardTitle className="text-base">
                      Source recordings
                    </CardTitle>
                    <CardDescription>
                      {visible.length} files in this period. Choose one to
                      inspect its motion.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    {!visible.length ? (
                      <Empty
                        icon={FileAudio}
                        title="No recordings in this period"
                      >
                        Try another period or import a Ciggy recording.
                      </Empty>
                    ) : (
                      <div className="max-h-[480px] overflow-y-auto">
                        {visible.map((session) => (
                          <div
                            key={session.id}
                            className={cn(
                              "flex items-start gap-3 border-t py-3",
                              active === session.id && "bg-muted/40",
                            )}
                          >
                            <button
                              className="min-w-0 flex-1 rounded-md p-2 text-left focus-visible:outline-2"
                              disabled={disabled || dirty}
                              onClick={() => selectRecording(session, true)}
                            >
                              <span className="flex items-center gap-2 text-sm font-medium">
                                {session.participant}
                                {active === session.id && (
                                  <Badge
                                    variant="outline"
                                    className="text-[10px]"
                                  >
                                    Selected
                                  </Badge>
                                )}
                              </span>
                              <span className="mt-1 block text-xs text-muted-foreground">
                                {dateTime.format(recordingBounds(session)[0])} ·{" "}
                                {duration(
                                  recordingBounds(session)[1] -
                                    recordingBounds(session)[0],
                                )}
                              </span>
                              <span className="mt-1 block text-[11px] text-muted-foreground">
                                {recordingSources(session)
                                  .map(sourceName)
                                  .join(" + ")}{" "}
                                ·{" "}
                                {(
                                  session.sampleCount ??
                                  session.recording.samples.length
                                ).toLocaleString()}{" "}
                                samples
                              </span>
                            </button>
                            <div className="flex pt-1">
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Rename participant"
                                disabled={disabled || dirty}
                                onClick={() =>
                                  openModal({ type: "rename", session })
                                }
                              >
                                <Pencil />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon-sm"
                                aria-label="Remove recording"
                                disabled={disabled || dirty}
                                onClick={() =>
                                  openModal({ type: "remove", session })
                                }
                              >
                                <Trash2 />
                              </Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
              <TabsContent value="delivery">
                <Delivery state={state} />
              </TabsContent>
            </Tabs>
          </section>

          <section ref={formRef} aria-labelledby="label-heading">
            <Card className="gap-5 shadow-none">
              <CardHeader>
                <div className="mb-1 flex items-center gap-2 text-[10px] font-semibold tracking-widest text-muted-foreground">
                  <Pencil className="size-3" />
                  ADD THE HUMAN PART
                </div>
                <CardTitle id="label-heading" className="text-lg">
                  What was happening?
                </CardTitle>
                <CardDescription className="text-xs">
                  A little context goes a long way.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <form onSubmit={saveLabel} className="space-y-4">
                  <Field label="Recording" id="label-recording">
                    <NativeSelect
                      id="label-recording"
                      value={active}
                      disabled={disabled || dirty || !visible.length}
                      onChange={(event) =>
                        selectRecording(
                          visible.find(
                            (session) => session.id === event.target.value,
                          ),
                        )
                      }
                    >
                      {!visible.length && (
                        <option value="">
                          Choose a period with recordings
                        </option>
                      )}
                      {visible.map((session) => (
                        <option value={session.id} key={session.id}>
                          {session.participant} ·{" "}
                          {dateTime.format(recordingBounds(session)[0])}
                        </option>
                      ))}
                    </NativeSelect>
                  </Field>
                  <Field label="From" id="label-start">
                    <Input
                      id="label-start"
                      type="datetime-local"
                      step="0.001"
                      required
                      disabled={disabled || !activeSession}
                      value={form.start}
                      onChange={(event) =>
                        updateForm("start", event.target.value)
                      }
                    />
                  </Field>
                  <Field label="To" id="label-end">
                    <Input
                      id="label-end"
                      type="datetime-local"
                      step="0.001"
                      required
                      disabled={disabled || !activeSession}
                      value={form.end}
                      onChange={(event) =>
                        updateForm("end", event.target.value)
                      }
                    />
                  </Field>
                  <Field label="Activity" id="label-activity">
                    <NativeSelect
                      id="label-activity"
                      value={form.activity}
                      disabled={disabled || !activeSession}
                      onChange={(event) =>
                        updateForm("activity", event.target.value)
                      }
                    >
                      {Object.entries(activities).map(([value, label]) => (
                        <option value={value} key={value}>
                          {label}
                        </option>
                      ))}
                    </NativeSelect>
                  </Field>
                  <Field label="Notes (optional)" id="label-notes">
                    <Textarea
                      id="label-notes"
                      rows={3}
                      maxLength={2000}
                      placeholder="Coffee break, walking, which hand…"
                      value={form.notes}
                      disabled={disabled || !activeSession}
                      onChange={(event) =>
                        updateForm("notes", event.target.value)
                      }
                    />
                  </Field>
                  <div className="flex gap-2">
                    <Button
                      className="flex-1"
                      type="submit"
                      disabled={
                        disabled ||
                        !activeSession ||
                        (activeSession.sampleCount ??
                          activeSession.recording.samples.length) < 2
                      }
                    >
                      <Plus />
                      {form.editing ? "Save changes" : "Save activity label"}
                    </Button>
                    {dirty && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={() =>
                          activeSession && selectRecording(activeSession)
                        }
                      >
                        Reset
                      </Button>
                    )}
                  </div>
                  <p className="text-[11px] leading-5 text-muted-foreground">
                    For back-to-back cigarettes, label each one separately.
                    Labels add context; they do not change your count or train
                    Ciggy automatically.
                  </p>
                </form>
              </CardContent>
            </Card>
          </section>
        </div>

        <footer className="flex flex-col justify-between gap-3 border-t pt-6 text-[11px] leading-5 text-muted-foreground sm:flex-row">
          <span className="shrink-0 font-medium text-neutral-500">
            Little wrist sidekick. Better understood.
          </span>
          <div className="max-w-2xl text-left sm:text-right">
            {connected ? (
              <>
                <span className="inline-flex items-center gap-1">
                  <LockKeyhole className="size-3" />
                  Private shared workspace
                </span>{" "}
                · Motion sharing is opt-in. Recordings and labels expire after{" "}
                {state.account.retentionDays ?? 14} days.
              </>
            ) : (
              "Browser-only imports stay on this device."
            )}
            <br />
            Gaps mean no recorded evidence. Background history has no gyroscope
            readings.
          </div>
        </footer>
      </main>

      <Dialog
        open={Boolean(modal)}
        onOpenChange={(open) => {
          if (!open && !working) setModal(null);
        }}
      >
        <DialogContent showCloseButton={!working}>
          <DialogHeader>
            <DialogTitle>
              {
                {
                  pair: "Connect your iPhone",
                  import: "Bring your recordings in",
                  rename: "Rename participant",
                  remove: "Remove this recording?",
                  deleteLabel: "Delete this activity label?",
                }[modal?.type]
              }
            </DialogTitle>
            <DialogDescription>
              {
                {
                  pair: "Create a private pairing code, then enter it in Ciggy on your iPhone.",
                  import: `${modal?.files?.length ?? 0} files selected. Saved labeled exports keep their participant names.`,
                  rename:
                    "This updates the name on this participant’s recordings.",
                  remove:
                    "The recording and its labels will be deleted. Export a copy first if you want to keep it.",
                  deleteLabel:
                    "This removes the observation. The original motion recording is kept.",
                }[modal?.type]
              }
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleModal} className="space-y-4">
            {["pair", "import", "rename"].includes(modal?.type) && (
              <Field label="Participant alias" id="modal-alias">
                <Input
                  id="modal-alias"
                  value={alias}
                  onChange={(event) => setAlias(event.target.value)}
                  required
                  maxLength={80}
                  autoComplete="off"
                  disabled={working || Boolean(pairing)}
                  placeholder="You, or a friend's alias"
                />
              </Field>
            )}
            {pairing && (
              <div className="rounded-xl border bg-white p-4">
                <p className="text-xs text-muted-foreground">
                  Enter this code in the iPhone app
                </p>
                <output className="my-3 block text-center font-mono text-2xl font-semibold tracking-widest">
                  {pairing.code}
                </output>
                <p className="text-xs text-muted-foreground">
                  Expires {dateTime.format(new Date(pairing.expiresAt))}. Use a
                  separate code for each participant.
                </p>
              </div>
            )}
            {modal?.type === "pair" && (
              <p className="text-xs leading-5 text-muted-foreground">
                Sharing is optional and can be turned off in Ciggy. Only
                consented recordings are uploaded.
              </p>
            )}
            {modal?.type === "import" && (
              <p className="text-xs text-muted-foreground">
                {connected
                  ? "Imports are saved to this private workspace and expire after 14 days."
                  : "Imports stay in this browser on this device."}
              </p>
            )}
            {modalError && (
              <p
                role="alert"
                className="rounded-md border border-neutral-500 p-3 text-sm"
              >
                {modalError}
              </p>
            )}
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                disabled={working}
                onClick={() => setModal(null)}
              >
                {pairing ? "Done" : "Cancel"}
              </Button>
              {!pairing && (
                <Button type="submit" disabled={working}>
                  {working
                    ? "Saving…"
                    : {
                        pair: "Create pairing code",
                        import: "Import recordings",
                        rename: "Save name",
                        remove: "Remove recording",
                        deleteLabel: "Delete label",
                      }[modal?.type]}
                </Button>
              )}
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
