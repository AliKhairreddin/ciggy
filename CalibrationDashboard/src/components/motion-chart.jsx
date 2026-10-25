import { useEffect, useRef, useState } from "react";
import { appleSecondsToMs, msToAppleSeconds } from "../../public/data.js";

const time = new Intl.DateTimeFormat(undefined, {
  hour: "numeric",
  minute: "2-digit",
  second: "2-digit",
});
const dayTime = new Intl.DateTimeFormat(undefined, {
  month: "short",
  day: "numeric",
  hour: "numeric",
  minute: "2-digit",
});
export const traceColor = (index) =>
  ["#171717", "#737373", "#404040", "#a3a3a3"][index % 4];

export function MotionChart({
  sessions,
  range,
  signal,
  axis,
  source,
  selection,
  loading,
  failed,
  onSelect,
}) {
  const canvasRef = useRef(null),
    drag = useRef(null);
  const [draft, setDraft] = useState(null),
    [tooltip, setTooltip] = useState(""),
    [hasSamples, setHasSamples] = useState(false);
  useEffect(() => {
    const canvas = canvasRef.current;
    function draw() {
      const { width, height } = canvas.getBoundingClientRect(),
        pixel = window.devicePixelRatio || 1;
      if (!width) return;
      canvas.width = width * pixel;
      canvas.height = height * pixel;
      const ctx = canvas.getContext("2d");
      ctx.scale(pixel, pixel);
      const [from, to] = range,
        span = Math.max(1, to - from),
        left = 46,
        right = width - 18,
        top = 25,
        bottom = height - 40;
      const x = (at) => left + ((at - from) / span) * (right - left);
      const points = sessions
        .flatMap((session) =>
          session.overview.bins
            .filter(
              (bin) =>
                (!source || bin.source === source) &&
                appleSecondsToMs(bin.end) >= from &&
                appleSecondsToMs(bin.start) <= to,
            )
            .map((bin) => ({
              session,
              bin,
              values: bin.values[signal]?.[axis],
            })),
        )
        .filter((point) => point.values);
      setHasSamples(points.length > 0);
      let low = 0,
        high = 0.05;
      for (const { values } of points) {
        low = Math.min(low, values[0]);
        high = Math.max(high, values[1]);
      }
      const spread = Math.max(0.05, high - low);
      high += spread * 0.08;
      if (low < 0) low -= spread * 0.08;
      const y = (value) =>
        bottom - ((value - low) / (high - low)) * (bottom - top);
      ctx.font = "11px -apple-system, sans-serif";
      for (let index = 0; index <= 4; index++) {
        const vertical = top + (index / 4) * (bottom - top);
        ctx.strokeStyle = "#ededed";
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(left, vertical);
        ctx.lineTo(right, vertical);
        ctx.stroke();
        ctx.fillStyle = "#737373";
        ctx.textAlign = "right";
        ctx.fillText(
          (high - (index / 4) * (high - low)).toFixed(2),
          left - 10,
          vertical + 3,
        );
      }
      const ticks = width < 500 ? 2 : 4;
      for (let index = 0; index <= ticks; index++) {
        ctx.textAlign =
          index === 0 ? "left" : index === ticks ? "right" : "center";
        const at = from + (index / ticks) * span;
        const format = span > 24 * 3600000 ? dayTime : time;
        ctx.fillText(
          format.format(at),
          left + (index / ticks) * (right - left),
          height - 13,
        );
      }
      ctx.save();
      ctx.beginPath();
      ctx.rect(left, top, right - left, bottom - top);
      ctx.clip();
      for (const session of sessions)
        for (const label of session.annotations ?? []) {
          ctx.fillStyle = "#17171708";
          ctx.fillRect(
            x(appleSecondsToMs(label.start)),
            top,
            Math.max(
              1,
              x(appleSecondsToMs(label.end)) - x(appleSecondsToMs(label.start)),
            ),
            bottom - top,
          );
        }
      const participants = [
        ...new Set(
          sessions.map(
            (session) => session.participantID ?? session.participant,
          ),
        ),
      ];
      const lines = Map.groupBy(
        points,
        (point) =>
          `${point.session.participantID ?? point.session.participant}:${point.bin.source}`,
      );
      for (const line of lines.values()) {
        line.sort((a, b) => a.bin.start - b.bin.start || b.bin.end - a.bin.end);
        ctx.strokeStyle = traceColor(
          participants.indexOf(
            line[0].session.participantID ?? line[0].session.participant,
          ),
        );
        ctx.lineWidth = 1.25;
        ctx.setLineDash(
          line[0].bin.source === "liveDeviceMotion" ? [3, 3] : [],
        );
        ctx.beginPath();
        let previousEnd = null;
        for (const { bin, values } of line) {
          if (previousEnd != null && bin.end <= previousEnd) continue;
          const start = Math.max(from, appleSecondsToMs(bin.start)),
            end = Math.min(to, appleSecondsToMs(bin.end));
          const at = (start + end) / 2;
          if (previousEnd == null || bin.start - previousEnd > 1)
            ctx.moveTo(x(at), y(values[1]));
          else ctx.lineTo(x(at), y(values[1]));
          ctx.moveTo(x(at), y(values[0]));
          ctx.lineTo(x(at), y(values[1]));
          ctx.moveTo(x(at), y(values[1]));
          if (bin.count === 1) ctx.rect(x(at) - 1, y(values[1]) - 1, 2, 2);
          previousEnd = bin.end;
        }
        ctx.stroke();
      }
      ctx.setLineDash([]);
      const marked = draft ?? selection;
      if (marked) {
        ctx.fillStyle = "#17171712";
        ctx.fillRect(
          x(marked[0]),
          top,
          x(marked[1]) - x(marked[0]),
          bottom - top,
        );
        ctx.strokeStyle = "#17171788";
        for (const at of marked) {
          ctx.beginPath();
          ctx.moveTo(x(at), top);
          ctx.lineTo(x(at), bottom);
          ctx.stroke();
        }
      }
      ctx.restore();
    }
    draw();
    const observer = new ResizeObserver(draw);
    observer.observe(canvas);
    return () => observer.disconnect();
  }, [sessions, range, signal, axis, source, selection, draft]);

  function pointerTime(event) {
    const box = canvasRef.current.getBoundingClientRect();
    return (
      range[0] +
      Math.max(
        0,
        Math.min(1, (event.clientX - box.left - 46) / (box.width - 64)),
      ) *
        (range[1] - range[0])
    );
  }
  function move(event) {
    const at = pointerTime(event);
    if (drag.current != null) {
      setDraft([Math.min(at, drag.current), Math.max(at, drag.current)]);
      return;
    }
    const seconds = msToAppleSeconds(at);
    const matches = sessions.flatMap((session) =>
      session.overview.bins
        .filter(
          (bin) =>
            seconds >= bin.start - 0.5 &&
            seconds <= bin.end + 0.5 &&
            (!source || source === bin.source) &&
            bin.values[signal]?.[axis],
        )
        .map(
          (bin) =>
            `${session.participant}: ${bin.values[signal][axis].map((value) => value.toFixed(3)).join("–")} ${signal === "rotationRate" ? "rad/s" : "g"}`,
        ),
    );
    setTooltip(
      `${time.format(at)} · ${matches.length ? matches.join(" · ") : "No measured samples"}`,
    );
  }
  return (
    <div className="relative">
      <canvas
        ref={canvasRef}
        className="chart-canvas"
        role="img"
        aria-label="Motion timeline. Drag to select an activity, or enter exact times in the activity form."
        onPointerDown={(event) => {
          if (event.button !== 0) return;
          drag.current = pointerTime(event);
          setTooltip("");
          event.currentTarget.setPointerCapture(event.pointerId);
        }}
        onPointerMove={move}
        onPointerLeave={() => setTooltip("")}
        onPointerUp={(event) => {
          if (drag.current == null) return;
          const at = pointerTime(event),
            selected = [Math.min(drag.current, at), Math.max(drag.current, at)];
          drag.current = null;
          setDraft(null);
          if (selected[1] > selected[0]) onSelect(selected);
        }}
        onPointerCancel={() => {
          drag.current = null;
          setDraft(null);
        }}
      />
      {!hasSamples && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center p-12 text-center text-sm text-muted-foreground">
          <span className="rounded-lg bg-white/95 px-4 py-3">
            {loading
              ? "Loading recorded motion…"
              : failed
                ? "Some motion could not load. Refresh to retry."
                : signal === "rotationRate"
                  ? "No gyroscope readings in this period. Background history has none."
                  : "No recorded motion in this period."}
          </span>
        </div>
      )}
      <div
        className="min-h-6 px-4 pb-2 text-xs text-muted-foreground"
        aria-hidden="true"
      >
        {tooltip || "Drag across the timeline to mark an activity."}
      </div>
    </div>
  );
}
