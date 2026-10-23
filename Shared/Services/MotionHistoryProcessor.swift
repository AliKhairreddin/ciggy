import Foundation

/// Missing source intervals remain retryable independently of the latest cursor.
public struct MotionHistoryRange: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

/// Streams recorded samples without loading hours of 50 Hz data into memory.
/// Unavailable queries are retained for reconciliation while later history advances.
public enum MotionHistoryProcessor {
    /// A bounded replay for timely display. This is deliberately separate from
    /// `Result`: its progress must never replace the chronological checkpoint,
    /// otherwise an older, unprocessed backlog would be lost.
    public struct RecentResult: Sendable {
        public let candidates: [DetectionCandidate]
        public let requestedFrom: Date
        public let processedThrough: Date
        public let latestSampleAt: Date?
        public let pendingRanges: [MotionHistoryRange]
        public let isComplete: Bool
    }

    public struct Result: Sendable {
        public let candidates: [DetectionCandidate]
        public let analyzer: RecordedMotionAnalyzer
        public let processedThrough: Date
        public let latestSampleAt: Date?
        public let pendingRanges: [MotionHistoryRange]
        public let expiredRangeCount: Int
    }

    /// Bounds used for both source queries and persisted cursor validation.
    public static func isSupportedDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }

    /// Checks recent activity before spending a limited background runtime on
    /// older history. Replaying eight preceding minutes reconstructs a session
    /// that straddles the recent-window boundary. Only candidates inside the
    /// requested window are returned. A fresh analyzer keeps this pass independent
    /// of the durable chronological cursor and makes unchanged source replays
    /// reproducible; callers still deduplicate against saved automatic sessions.
    public static func processRecent(
        from start: Date,
        to end: Date,
        sensitivity: Double,
        lookbackSeconds: TimeInterval = 45 * 60,
        query: (Date, Date) -> AnySequence<RecordedAccelerationSample>?,
        shouldContinue: () -> Bool = { true }
    ) -> RecentResult {
        guard isSupportedDate(start), isSupportedDate(end), start < end else {
            let safeCursor = isSupportedDate(start) ? start : (isSupportedDate(end) ? end : Date(timeIntervalSince1970: 0))
            return .init(candidates: [], requestedFrom: safeCursor, processedThrough: safeCursor,
                         latestSampleAt: nil, pendingRanges: [], isComplete: start == end && isSupportedDate(start))
        }
        let lookback = lookbackSeconds.isFinite ? min(3 * 60 * 60, max(60, lookbackSeconds)) : 45 * 60
        let requestedFrom = max(start, end.addingTimeInterval(-lookback))
        let replayFrom = max(requestedFrom.addingTimeInterval(-8 * 60), end.addingTimeInterval(-3 * 24 * 60 * 60))
        let replay = process(
            from: replayFrom, to: end, analyzer: .init(sensitivity: sensitivity),
            pendingRanges: [], sensitivity: sensitivity, queryChunkDuration: 15 * 60,
            query: query, shouldContinue: shouldContinue
        )
        return .init(
            candidates: replay.candidates.filter { $0.gestureAt >= requestedFrom && $0.gestureAt <= end },
            requestedFrom: requestedFrom,
            processedThrough: replay.processedThrough,
            latestSampleAt: replay.latestSampleAt,
            pendingRanges: replay.pendingRanges,
            isComplete: replay.processedThrough >= end && replay.pendingRanges.isEmpty
        )
    }

    public static func process(
        from start: Date,
        to end: Date,
        analyzer initialAnalyzer: RecordedMotionAnalyzer,
        pendingRanges: [MotionHistoryRange],
        sensitivity: Double,
        queryChunkDuration: TimeInterval = 30 * 60,
        query: (Date, Date) -> AnySequence<RecordedAccelerationSample>?,
        shouldContinue: () -> Bool = { true }
    ) -> Result {
        guard isSupportedDate(start), isSupportedDate(end), start <= end else {
            let safeCursor = isSupportedDate(start) ? start : (isSupportedDate(end) ? end : Date(timeIntervalSince1970: 0))
            return .init(candidates: [], analyzer: initialAnalyzer, processedThrough: safeCursor,
                         latestSampleAt: nil, pendingRanges: [], expiredRangeCount: 0)
        }
        var analyzer = initialAnalyzer
        var candidates: [DetectionCandidate] = []
        var pending: [MotionHistoryRange] = []
        var latestSampleAt: Date?
        let retentionStart = end.addingTimeInterval(-3 * 24 * 60 * 60)
        var processedThrough = max(start, retentionStart)
        let chunkDuration = queryChunkDuration.isFinite ? max(1, min(12 * 60 * 60, queryChunkDuration)) : 30 * 60
        let validRanges = pendingRanges.filter { isSupportedDate($0.start) && isSupportedDate($0.end) && $0.start < $0.end }
        let retryRanges = coalescedRanges(validRanges.compactMap { range in
            let lower = max(range.start, retentionStart)
            let upper = min(range.end, end)
            return lower < upper ? .init(start: lower, end: upper) : nil
        }, maximumDuration: chunkDuration)
        var sampleCount = 0

        func consume(_ samples: AnySequence<RecordedAccelerationSample>, from lower: Date, to upper: Date,
                     using engine: inout RecordedMotionAnalyzer, progress: inout Date) -> Bool {
            for sample in samples {
                sampleCount += 1
                if sampleCount.isMultiple(of: 512), shouldContinue() == false { return false }
                guard sample.timestamp >= lower, sample.timestamp <= upper else { continue }
                // Let the analyzer see malformed acceleration so it can cancel a
                // partial gesture; filtering it out would join across bad data.
                if let candidate = engine.record(sample) { candidates.append(candidate) }
                guard sample.x.isFinite, sample.y.isFinite, sample.z.isFinite else { continue }
                progress = max(progress, sample.timestamp)
                latestSampleAt = max(latestSampleAt ?? sample.timestamp, sample.timestamp)
            }
            return true
        }

        while processedThrough < end && shouldContinue() {
            let queryStart = processedThrough
            let queryEnd = min(queryStart.addingTimeInterval(chunkDuration), end)
            guard let samples = query(queryStart, queryEnd) else {
                pending.append(.init(start: queryStart, end: queryEnd))
                processedThrough = queryEnd
                continue
            }
            guard consume(samples, from: queryStart, to: queryEnd, using: &analyzer, progress: &processedThrough) else { break }
            // A non-nil enumerated result is the provider's completed query,
            // including a valid empty interval. nil remains in pendingRanges.
            processedThrough = queryEnd
        }

        // Replays include neighboring motion so a missing chunk at a cigarette
        // boundary can reconstruct the session without inventing sensor samples.
        for range in retryRanges {
            guard shouldContinue() else { pending.append(range); continue }
            var replay = RecordedMotionAnalyzer(sensitivity: sensitivity)
            var cursor = max(range.start.addingTimeInterval(-8 * 60), retentionStart)
            let replayEnd = min(range.end.addingTimeInterval(8 * 60), end)
            var complete = true
            while cursor < replayEnd {
                guard shouldContinue() else { complete = false; break }
                let upper = min(cursor.addingTimeInterval(chunkDuration), replayEnd)
                guard let samples = query(cursor, upper) else { complete = false; break }
                var progress = cursor
                guard consume(samples, from: cursor, to: upper, using: &replay, progress: &progress) else {
                    complete = false; break
                }
                cursor = upper
            }
            if complete == false || range.end.addingTimeInterval(8 * 60) > end { pending.append(range) }
        }

        return .init(candidates: candidates, analyzer: analyzer, processedThrough: processedThrough,
                     latestSampleAt: latestSampleAt,
                     pendingRanges: coalescedRanges(pending, maximumDuration: chunkDuration),
                     expiredRangeCount: validRanges.filter { $0.end <= retentionStart }.count)
    }

    /// One-minute foreground retries must not create thousands of adjacent
    /// requests. Combine coverage, then split into bounded replay batches.
    private static func coalescedRanges(_ ranges: [MotionHistoryRange], maximumDuration: TimeInterval) -> [MotionHistoryRange] {
        var unions: [MotionHistoryRange] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if let last = unions.last, range.start <= last.end {
                unions[unions.count - 1] = .init(start: last.start, end: max(last.end, range.end))
            } else { unions.append(range) }
        }
        var batches: [MotionHistoryRange] = []
        for range in unions {
            var cursor = range.start
            while cursor < range.end {
                let upper = min(cursor.addingTimeInterval(maximumDuration), range.end)
                guard upper > cursor else { break }
                batches.append(.init(start: cursor, end: upper))
                cursor = upper
            }
        }
        return batches
    }
}
