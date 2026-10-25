import {
  cleanAlias,
  validateRecording,
  mergeRemotePage,
  mergeSessions,
} from "../../public/data.js";
import { loadSessions, saveSessions } from "../../public/storage.js";
import { summarizeRecording } from "../../public/timeline.js";
import { initialFilters, periodBounds } from "./period.js";

export async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: "same-origin",
    ...options,
    headers: { "Content-Type": "application/json", ...options.headers },
  });
  const body = response.headers
    .get("content-type")
    ?.includes("application/json")
    ? await response.json()
    : null;
  if (response.status === 409)
    throw new Error(
      "Another reviewer changed these labels. Refresh recordings before trying again.",
    );
  if (!response.ok || !body)
    throw new Error(
      body?.error ??
        "The private workspace could not be reached. Sign in again or try refreshing.",
    );
  return body;
}

// The service remains the durable source. Metadata is reconciled every five
// minutes; intervening polls use the newest page. Raw files are loaded on demand.
export function createJournal() {
  let state = {
    sessions: [],
    overviews: new Map(),
    failures: new Set(),
    filters: initialFilters(),
    range: periodBounds(initialFilters()),
    mode: "loading",
    busy: false,
    hydrating: false,
    notice: null,
    account: null,
    delivery: [],
    deliveryError: false,
    updatedAt: null,
  };
  const listeners = new Set(),
    cache = new Map(),
    pendingRaw = new Map();
  let lastFull = 0,
    generation = 0,
    initialization;
  const emit = (changes) => {
    state = { ...state, ...changes };
    listeners.forEach((listener) => listener());
  };
  const notice = (message, error = false) =>
    emit({ notice: message ? { message, error } : null });
  const connected = () => state.mode === "connected";

  async function hydrate() {
    const current = ++generation;
    emit({ hydrating: true });
    const pending = state.sessions.filter((session) => {
      const saved = state.overviews.get(session.id);
      return (
        !saved ||
        saved.labelRevision !== session.labelRevision ||
        saved.participant !== session.participant
      );
    });
    for (let offset = 0; offset < pending.length; offset += 3) {
      if (current !== generation) return;
      const results = await Promise.allSettled(
        pending.slice(offset, offset + 3).map(async (metadata) => {
          const summary = metadata.remote
            ? await api(
                `/api/recordings/${encodeURIComponent(metadata.id)}/overview`,
              )
            : { ...metadata, overview: summarizeRecording(metadata.recording) };
          return { ...metadata, ...summary };
        }),
      );
      if (current !== generation) return;
      const overviews = new Map(state.overviews),
        failures = new Set(state.failures);
      results.forEach((result, index) => {
        const id = pending[offset + index].id;
        if (result.status === "fulfilled") {
          overviews.set(id, result.value);
          failures.delete(id);
        } else failures.add(id);
      });
      emit({ overviews, failures });
    }
    emit({ hydrating: false });
  }

  async function refresh(
    filters = state.filters,
    { incremental = false, localFilter = false } = {},
  ) {
    if (state.busy) return false;
    if (localFilter) {
      emit({ filters });
      return true;
    }
    const now = Date.now(),
      range = periodBounds(filters, {
        now,
        sessions: state.sessions,
        connected: connected(),
      });
    emit({ busy: true });
    try {
      let sessions = state.sessions;
      if (connected()) {
        sessions = [];
        const recentOnly =
          incremental &&
          JSON.stringify(filters) === JSON.stringify(state.filters) &&
          lastFull > 0 &&
          now - lastFull < 300000;
        let cursor = null;
        const seen = new Set();
        do {
          const query = new URLSearchParams({
            from: new Date(range[0]).toISOString(),
            to: new Date(range[1]).toISOString(),
            limit: "200",
          });
          if (cursor) query.set("cursor", cursor);
          const page = await api(`/api/recordings?${query}`);
          if (!Array.isArray(page.recordings))
            throw new Error("The recording list could not be read.");
          sessions.push(
            ...page.recordings.map((session) => ({ ...session, remote: true })),
          );
          cursor = page.nextCursor;
          if (cursor && (!page.recordings.length || seen.has(cursor)))
            throw new Error(
              "The recording list was incomplete. Previously loaded data is kept; try Refresh.",
            );
          if (cursor) seen.add(cursor);
          if (recentOnly) {
            sessions = mergeRemotePage(state.sessions, sessions, {
              hasMore: Boolean(cursor),
              fromMs: range[0],
              toMs: range[1],
              nowMs: now,
            });
            break;
          }
          if (sessions.length >= 12000 && cursor)
            throw new Error(
              "Too many recordings for one view. Choose a shorter period. Saved data is kept.",
            );
        } while (cursor);
        if (!recentOnly) lastFull = now;
        for (const session of sessions) {
          const saved = cache.get(session.id);
          if (
            saved &&
            (saved.labelRevision !== session.labelRevision ||
              saved.participant !== session.participant)
          )
            cache.delete(session.id);
        }
      }
      const ids = new Set(sessions.map((session) => session.id));
      for (const id of cache.keys()) if (!ids.has(id)) cache.delete(id);
      const overviews = new Map(
        [...state.overviews].filter(([id]) => ids.has(id)),
      );
      // Do not display an outdated label revision while its summary is loading.
      for (const session of sessions) {
        const saved = overviews.get(session.id);
        if (
          saved &&
          (saved.labelRevision !== session.labelRevision ||
            saved.participant !== session.participant)
        )
          overviews.delete(session.id);
      }
      emit({
        sessions,
        filters,
        range,
        overviews,
        failures: new Set(),
        updatedAt: now,
      });
      void hydrate();
      if (connected()) {
        try {
          const result = await api("/api/delivery");
          if (!Array.isArray(result.participants))
            throw new Error("Invalid delivery report");
          emit({ delivery: result.participants, deliveryError: false });
        } catch {
          emit({ deliveryError: true });
        }
      }
      return true;
    } catch (error) {
      notice(`${error.message} The previous view is kept.`, true);
      return false;
    } finally {
      emit({ busy: false });
    }
  }

  async function initialize() {
    try {
      const response = await fetch("/api/session", {
        credentials: "same-origin",
      });
      if (
        response.ok &&
        response.headers.get("content-type")?.includes("application/json")
      ) {
        emit({ mode: "connected", account: await response.json() });
      } else if (response.status === 404) {
        emit({ mode: "local", sessions: await loadSessions() });
      } else
        throw new Error(
          "Sign in to open the private workspace. Refresh this page to try again.",
        );
      await refresh();
    } catch (error) {
      emit({ mode: "error" });
      notice(error.message, true);
    }
  }

  async function getSession(id) {
    if (cache.has(id)) return cache.get(id);
    if (pendingRaw.has(id)) return pendingRaw.get(id);
    const metadata = state.sessions.find((session) => session.id === id);
    if (!metadata) throw new Error("This recording is no longer available.");
    const promise = (async () => {
      const session = metadata.remote
        ? {
            ...(await api(`/api/recordings/${encodeURIComponent(id)}`)),
            remote: true,
          }
        : metadata;
      session.recording = validateRecording(session.recording);
      cache.set(id, session);
      if (cache.size > 25) cache.delete(cache.keys().next().value);
      return session;
    })();
    pendingRaw.set(id, promise);
    try {
      return await promise;
    } finally {
      pendingRaw.delete(id);
    }
  }

  async function persistLabels(session, annotations) {
    let updated = { ...session, annotations };
    if (session.remote) {
      const result = await api(
        `/api/recordings/${encodeURIComponent(session.id)}/labels`,
        {
          method: "PUT",
          body: JSON.stringify({
            annotations,
            expectedRevision: session.labelRevision,
          }),
        },
      );
      updated = {
        ...updated,
        annotations: result.annotations ?? annotations,
        labelRevision: result.labelRevision,
      };
    } else await saveSessions([updated]);
    cache.set(session.id, updated);
    const overviews = new Map(state.overviews),
      overview = overviews.get(session.id);
    if (overview)
      overviews.set(session.id, {
        ...overview,
        annotations: updated.annotations,
        labelRevision: updated.labelRevision,
      });
    emit({
      overviews,
      sessions: state.sessions.map((metadata) =>
        metadata.id === session.id
          ? session.remote
            ? {
                ...metadata,
                annotationCount: updated.annotations.length,
                labelRevision: updated.labelRevision,
              }
            : updated
          : metadata,
      ),
    });
    void hydrate();
  }

  async function importSessions(incoming) {
    if (connected()) {
      let added = 0;
      try {
        for (const session of incoming) {
          await api("/api/import", {
            method: "POST",
            body: JSON.stringify({
              participant: session.participant,
              recording: session.recording,
              annotations: session.annotations,
            }),
          });
          added++;
        }
      } catch (error) {
        await refresh();
        throw new Error(
          `${added} recordings saved before the import stopped. ${error.message}`,
        );
      }
      cache.clear();
      await refresh();
      return `${added} recordings imported. Existing recordings keep their labels.`;
    }
    const result = mergeSessions(state.sessions, incoming);
    const added = result.sessions.filter(
      (session) =>
        !state.sessions.some((existing) => existing.id === session.id),
    );
    await saveSessions(added);
    emit({ sessions: result.sessions });
    await refresh();
    return `${result.added} recordings imported${result.duplicate ? ` · ${result.duplicate} already saved` : ""}.`;
  }

  async function rename(session, value) {
    const alias = cleanAlias(value);
    if (session.remote) {
      await api(
        `/api/participants/${encodeURIComponent(session.participantID)}`,
        { method: "PATCH", body: JSON.stringify({ alias }) },
      );
      cache.clear();
      await refresh();
    } else {
      const updated = state.sessions
        .filter((item) => item.participant === session.participant)
        .map((item) => ({ ...item, participant: alias }));
      await saveSessions(updated);
      cache.clear();
      emit({
        sessions: state.sessions.map(
          (item) =>
            updated.find((replacement) => replacement.id === item.id) ?? item,
        ),
      });
      await refresh({
        ...state.filters,
        participant:
          state.filters.participant === session.participant
            ? alias
            : state.filters.participant,
      });
    }
    notice("Participant name updated.");
  }

  async function remove(session) {
    if (session.remote)
      await api(`/api/recordings/${encodeURIComponent(session.id)}`, {
        method: "DELETE",
      });
    else await saveSessions([], [session.id]);
    cache.delete(session.id);
    const overviews = new Map(state.overviews);
    overviews.delete(session.id);
    emit({
      sessions: state.sessions.filter((item) => item.id !== session.id),
      overviews,
    });
    void hydrate();
    notice("Recording and its labels removed.");
  }

  return {
    subscribe: (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    getSnapshot: () => state,
    initialize: () => (initialization ??= initialize()),
    refresh,
    notice,
    getSession,
    persistLabels,
    importSessions,
    rename,
    remove,
  };
}
