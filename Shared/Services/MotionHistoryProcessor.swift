import Foundation

/// Missing source intervals remain retryable independently of the latest cursor.
public struct MotionHistoryRange: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
}

/// Classifier state before a missing interval, plus safe replay progress. Saving
/// this together with the candidates makes interrupted reconciliation resumable.
public struct MotionHistoryReplayCheckpoint: Codable, Sendable {
    public let range: MotionHistoryRange
    public let origin: Date
    public let processedThrough: Date
    public let analyzer: RecordedMotionAnalyzer
    public let originAnalyzer: RecordedMotionAnalyzer?
    public let hasUnresolvedCoverage: Bool?

    public init(range: MotionHistoryRange, origin: Date, processedThrough: Date, analyzer: RecordedMotionAnalyzer,
                originAnalyzer: RecordedMotionAnalyzer? = nil, hasUnresolvedCoverage: Bool? = nil) {
        self.range = range; self.origin = origin
        self.processedThrough = processedThrough; self.analyzer = analyzer
        self.originAnalyzer = originAnalyzer; self.hasUnresolvedCoverage = hasUnresolvedCoverage
    }
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
        public let replayCheckpoints: [MotionHistoryReplayCheckpoint]
    }

    /// Bounds used for both source queries and persisted cursor validation.
    public static func isSupportedDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }

    /// Checks recent activity before spending a limited background runtime on
    /// older history. Replaying eight preceding minutes reconstructs a session
    /// that straddles the recent-window boundary. Only candidates inside the
    /// requested window are returned. When the chronological checkpoint is inside
    /// that context, copy its analyzer and continue from its cursor: restarting
    /// midway through an already counted pattern could count that cigarette again.
    /// Older backlogs use a fresh bounded replay. Neither pass advances the caller's
    /// durable chronological checkpoint; callers still deduplicate saved sessions.
    public static func processRecent(
        from start: Date,
        to end: Date,
        analyzer initialAnalyzer: RecordedMotionAnalyzer? = nil,
        sourceStartedAt: Date? = nil,
        sensitivity: Double,
        lookbackSeconds: TimeInterval = TrackingRefreshPolicy.recentLookback,
        query: (Date, Date) -> AnySequence<RecordedAccelerationSample>?,
        shouldContinue: () -> Bool = { true }
    ) -> RecentResult {
        guard isSupportedDate(start), isSupportedDate(end), start < end else {
            let safeCursor = isSupportedDate(start) ? start : (isSupportedDate(end) ? end : Date(timeIntervalSince1970: 0))
            return .init(candidates: [], requestedFrom: safeCursor, processedThrough: safeCursor,
                         latestSampleAt: nil, pendingRanges: [], isComplete: start == end && isSupportedDate(start))
        }
        let lookback = lookbackSeconds.isFinite ? min(3 * 60 * 60, max(60, lookbackSeconds)) : TrackingRefreshPolicy.recentLookback
        let requestedFrom = max(start, end.addingTimeInterval(-lookback))
        let contextStart = max(requestedFrom.addingTimeInterval(-8 * 60), end.addingTimeInterval(-3 * 24 * 60 * 60))
        let checkpoint = start >= contextStart ? initialAnalyzer : nil
        let sourceStart = sourceStartedAt.flatMap { isSupportedDate($0) && $0 <= end ? $0 : nil }
        let replayFrom = checkpoint == nil ? max(contextStart, sourceStart ?? contextStart) : start
        var analyzer = checkpoint ?? RecordedMotionAnalyzer(
            sensitivity: sensitivity, requiresConfirmedBoundary: sourceStart != replayFrom
        )
        analyzer.updateSensitivity(sensitivity)
        let replay = process(
            from: replayFrom, to: end, analyzer: analyzer,
            pendingRanges: [], sourceStartedAt: sourceStart, sensitivity: sensitivity, queryChunkDuration: 15 * 60,
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
        replayCheckpoints: [MotionHistoryReplayCheckpoint] = [],
        sourceStartedAt: Date? = nil,
        sensitivity: Double,
        queryChunkDuration: TimeInterval = 30 * 60,
        query: (Date, Date) -> AnySequence<RecordedAccelerationSample>?,
        shouldContinue: () -> Bool = { true }
    ) -> Result {
        guard isSupportedDate(start), isSupportedDate(end), start <= end else {
            let safeCursor = isSupportedDate(start) ? start : (isSupportedDate(end) ? end : Date(timeIntervalSince1970: 0))
            return .init(candidates: [], analyzer: initialAnalyzer, processedThrough: safeCursor,
                         latestSampleAt: nil, pendingRanges: [], expiredRangeCount: 0, replayCheckpoints: [])
        }
        var analyzer = initialAnalyzer
        var candidates: [DetectionCandidate] = []
        var pending: [MotionHistoryRange] = []
        var checkpoints: [MotionHistoryReplayCheckpoint] = []
        var latestSampleAt: Date?
        let retentionStart = end.addingTimeInterval(-3 * 24 * 60 * 60)
        var processedThrough = max(start, retentionStart)
        if start < retentionStart { analyzer.sourceBecameUnavailable() }
        let sourceStart = sourceStartedAt.flatMap { isSupportedDate($0) && $0 <= end ? $0 : nil }
        let chunkDuration = queryChunkDuration.isFinite ? max(1, min(12 * 60 * 60, queryChunkDuration)) : 30 * 60
        let validRanges = pendingRanges.filter { isSupportedDate($0.start) && isSupportedDate($0.end) && $0.start < $0.end }
        let retryRanges = coalescedRanges(validRanges.compactMap { range in
            let lower = max(range.start, retentionStart)
            let upper = min(range.end, end)
            return lower < upper ? .init(start: lower, end: upper) : nil
        }, maximumDuration: chunkDuration)
        var sampleCount = 0

        enum Consumption { case complete, interrupted }
        func consume(_ samples: AnySequence<RecordedAccelerationSample>, from lower: Date, to upper: Date,
                     using engine: inout RecordedMotionAnalyzer, progress: inout Date,
                     uncertain: inout Bool) -> Consumption {
            var firstValidAt: Date?
            var lastValidAt: Date?
            for sample in samples {
                sampleCount += 1
                if sampleCount.isMultiple(of: 512), shouldContinue() == false { return .interrupted }
                let validTimestamp = isSupportedDate(sample.timestamp)
                if validTimestamp && (sample.timestamp < lower || sample.timestamp > upper) { continue }
                if validTimestamp, firstValidAt == nil, sample.timestamp.timeIntervalSince(lower) > 1 {
                    uncertain = true
                    engine.sourceBecameUnavailable()
                }
                let disruptions = engine.sourceDisruptionCount
                let deferred = engine.deferredCandidateCount
                if let candidate = engine.record(sample) { candidates.append(candidate) }
                if engine.sourceDisruptionCount != disruptions || engine.deferredCandidateCount != deferred {
                    uncertain = true
                }
                let acceleration = MotionVector(x: sample.x, y: sample.y, z: sample.z)
                guard validTimestamp, acceleration.isFinite, acceleration.magnitude.isFinite,
                      acceleration.magnitude > 0.01 else { continue }
                if firstValidAt == nil, sample.timestamp.timeIntervalSince(lower) > 1 { uncertain = true }
                firstValidAt = min(firstValidAt ?? sample.timestamp, sample.timestamp)
                lastValidAt = max(lastValidAt ?? sample.timestamp, sample.timestamp)
                progress = max(progress, sample.timestamp)
                latestSampleAt = max(latestSampleAt ?? sample.timestamp, sample.timestamp)
            }
            // Enumerating a result does not prove it contained the requested
            // source. Empty and clipped queries remain retryable; neither can
            // manufacture the observed quiet needed to establish a boundary.
            if firstValidAt.map({ $0.timeIntervalSince(lower) > 1 }) ?? true { uncertain = true }
            if lastValidAt.map({ upper.timeIntervalSince($0) > 1 }) ?? true {
                uncertain = true
                engine.sourceBecameUnavailable()
            }
            return .complete
        }

        // Repair from the original classifier state before advancing new history.
        // Each successful source chunk checkpoints its exact analyzer/cursor, so
        // a short background budget still makes progress across a large backlog.
        var reconciledThrough: Date?
        var sharedRetry: MotionHistoryReplayCheckpoint?
        for range in retryRanges {
            if let reconciledThrough, range.end <= reconciledThrough { continue }
            if let sharedRetry {
                // The earliest repair already scans all later source. Reuse its
                // resumable state for adjacent gaps instead of querying the same
                // three-day backlog once for each missing interval.
                pending.append(range)
                checkpoints.append(.init(range: range, origin: sharedRetry.origin,
                    processedThrough: sharedRetry.processedThrough, analyzer: sharedRetry.analyzer,
                    originAnalyzer: sharedRetry.originAnalyzer, hasUnresolvedCoverage: sharedRetry.hasUnresolvedCoverage))
                continue
            }
            let saved = replayCheckpoints.first {
                $0.range.start == range.start && $0.range.end <= range.end &&
                isSupportedDate($0.origin) && isSupportedDate($0.processedThrough) &&
                $0.origin >= retentionStart && $0.origin <= range.start &&
                $0.processedThrough >= $0.origin && $0.processedThrough <= end &&
                ($0.originAnalyzer != nil || $0.processedThrough == $0.origin)
            }
            let origin: Date
            let original: RecordedMotionAnalyzer
            var cursor: Date
            var replay: RecordedMotionAnalyzer
            var unresolved = saved?.hasUnresolvedCoverage ?? false
            if let saved {
                origin = saved.origin; cursor = saved.processedThrough; replay = saved.analyzer
                original = saved.originAnalyzer ?? saved.analyzer
            } else {
                // Legacy gaps have no preceding analyzer. Start at the known
                // capture origin when retained; otherwise require measured quiet
                // before trusting any episode at the source's truncated left edge.
                origin = max(sourceStart ?? retentionStart, retentionStart)
                cursor = origin
                replay = .init(sensitivity: sensitivity, requiresConfirmedBoundary: sourceStart != origin)
                original = replay
            }
            replay.updateSensitivity(sensitivity)
            var complete = true
            while cursor < end {
                guard shouldContinue() else { complete = false; break }
                let lower = cursor
                let upper = min(lower.addingTimeInterval(chunkDuration), end)
                guard let samples = query(lower, upper) else {
                    unresolved = true
                    replay.sourceBecameUnavailable()
                    cursor = upper
                    continue
                }
                var uncertain = false
                let outcome = consume(samples, from: lower, to: upper, using: &replay, progress: &cursor,
                                      uncertain: &uncertain)
                unresolved = unresolved || uncertain
                if outcome == .interrupted { complete = false; break }
                cursor = upper
            }
            if complete && unresolved == false {
                // Only a fully covered chronological replay can replace current
                // state. It includes all successors, not merely eight minutes.
                analyzer = replay
                processedThrough = end
                reconciledThrough = end
            } else {
                pending.append(range)
                // Continue beyond an unresolved prefix to find later episodes
                // with measured boundaries. After the pass, retry from the exact
                // pre-gap state; interruption instead resumes its current cursor.
                let savedRetry = MotionHistoryReplayCheckpoint(range: range, origin: origin,
                    processedThrough: complete ? origin : cursor,
                    analyzer: complete ? original : replay,
                    originAnalyzer: original, hasUnresolvedCoverage: complete ? false : unresolved)
                checkpoints.append(savedRetry)
                sharedRetry = savedRetry
            }
        }

        while processedThrough < end && shouldContinue() {
            let queryStart = processedThrough
            let queryEnd = min(queryStart.addingTimeInterval(chunkDuration), end)
            let before = analyzer
            let range = MotionHistoryRange(start: queryStart, end: queryEnd)
            let origin = max(retentionStart, min(queryStart, before.latestProcessedSampleAt ?? queryStart))
            guard let samples = query(queryStart, queryEnd) else {
                pending.append(range)
                checkpoints.append(.init(range: range, origin: origin, processedThrough: origin, analyzer: before, originAnalyzer: before))
                analyzer.sourceBecameUnavailable()
                processedThrough = queryEnd
                continue
            }
            var uncertain = false
            let outcome = consume(samples, from: queryStart, to: queryEnd, using: &analyzer, progress: &processedThrough,
                                  uncertain: &uncertain)
            if uncertain {
                pending.append(range)
                checkpoints.append(.init(range: range, origin: origin, processedThrough: origin, analyzer: before, originAnalyzer: before))
            }
            if outcome == .interrupted { break }
            // A completed empty query is not manufactured quiet. The analyzer
            // only proves boundaries from continuous, valid observed samples.
            processedThrough = queryEnd
        }

        let remaining = coalescedRanges(pending, maximumDuration: chunkDuration)
        let retainedCheckpoints = remaining.compactMap { range -> MotionHistoryReplayCheckpoint? in
            guard let saved = checkpoints.first(where: { $0.range.start == range.start }) else { return nil }
            return .init(range: range, origin: saved.origin, processedThrough: saved.processedThrough, analyzer: saved.analyzer,
                         originAnalyzer: saved.originAnalyzer, hasUnresolvedCoverage: saved.hasUnresolvedCoverage)
        }
        return .init(candidates: candidates, analyzer: analyzer, processedThrough: processedThrough,
                     latestSampleAt: latestSampleAt, pendingRanges: remaining,
                     expiredRangeCount: validRanges.filter { $0.start < retentionStart }.count,
                     replayCheckpoints: retainedCheckpoints)
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
