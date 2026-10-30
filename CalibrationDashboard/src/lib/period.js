import { reviewQuery } from "../../public/review-link.js";
import { appleSecondsToMs } from "../../public/data.js";

export const HOUR = 3600000;
export const timeInput = (ms) => {
  const date = new Date(ms);
  return new Date(ms - date.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 23);
};
export const recordingBounds = (session) =>
  session.recording
    ? [
        appleSecondsToMs(session.recording.samples[0].timestamp),
        appleSecondsToMs(session.recording.samples.at(-1).timestamp),
      ]
    : [Date.parse(session.startedAt), Date.parse(session.endedAt)];
export const recordingSources = (session) =>
  session.sources ?? [
    ...new Set(session.recording.samples.map((sample) => sample.source)),
  ];
export const initialFilters = (search = globalThis.location?.search ?? "") => {
  const query = new URLSearchParams(reviewQuery(search));
  return {
    period: query.has("from") ? "custom" : "48h",
    day: timeInput(Date.now()).slice(0, 10),
    start: query.has("from") ? timeInput(Date.parse(query.get("from"))) : "",
    end: query.has("to") ? timeInput(Date.parse(query.get("to"))) : "",
    participant: query.get("participant") ?? "",
    source: "",
  };
};

// Calendar presets use local midnight, so a DST day can have 23 or 25 hours.
export function periodBounds(
  filters,
  { now = Date.now(), sessions = [], connected = false } = {},
) {
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  let range;
  switch (filters.period) {
    case "today":
      range = [+today, Math.max(+today + 1, now)];
      break;
    case "yesterday": {
      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      range = [+yesterday, +today];
      break;
    }
    case "day": {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(filters.day))
        throw new Error("Choose a valid day.");
      const day = new Date(`${filters.day}T00:00:00`),
        end = new Date(day);
      if (
        !Number.isFinite(+day) ||
        timeInput(+day).slice(0, 10) !== filters.day
      )
        throw new Error("Choose a valid day.");
      end.setDate(end.getDate() + 1);
      range = [+day, +end];
      break;
    }
    case "custom":
      range = [
        new Date(filters.start).getTime(),
        new Date(filters.end).getTime(),
      ];
      break;
    case "all": {
      const times = sessions.flatMap(recordingBounds).filter(Number.isFinite);
      range =
        !connected && times.length
          ? [Math.min(...times), Math.max(...times) + 1]
          : [now - 14 * 24 * HOUR, now];
      break;
    }
    case "7d":
      range = [now - 7 * 24 * HOUR, now];
      break;
    case "24h":
      range = [now - 24 * HOUR, now];
      break;
    case "1h":
      range = [now - HOUR, now];
      break;
    default:
      range = [now - 48 * HOUR, now];
  }
  if (!range.every(Number.isFinite))
    throw new Error("Choose both a start and an end date and time.");
  if (range[0] >= range[1]) throw new Error("The end must be after the start.");
  return range;
}

export function filterSessions(sessions, filters, range) {
  return sessions
    .filter((session) => {
      const [start, end] = recordingBounds(session);
      return (
        end >= range[0] &&
        start <= range[1] &&
        (!filters.participant ||
          (session.participantID ?? session.participant) ===
            filters.participant) &&
        (!filters.source || recordingSources(session).includes(filters.source))
      );
    })
    .sort((a, b) => recordingBounds(b)[0] - recordingBounds(a)[0]);
}

export function constrainView(view, period) {
  const span = Math.min(period[1] - period[0], Math.max(1, view[1] - view[0]));
  const start = Math.max(period[0], Math.min(view[0], period[1] - span));
  return [start, start + span];
}
