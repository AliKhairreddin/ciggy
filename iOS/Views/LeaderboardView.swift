#if os(iOS)
import CiggyShared
import SwiftUI

/// Public standings expose weekly aggregates without sharing individual smoking events.
struct LeaderboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var repository: EventRepository
    @EnvironmentObject private var league: LeaderboardStore
    @State private var consentsToPublicProfile = false
    @State private var confirmsLeaving = false

    private var palette: CiggyPalette { CiggyPalette(colorScheme: colorScheme) }

    var body: some View {
        CiggyAdaptiveScreen {
            header
            leagueHero
            membershipCard
            seasonPicker
            standings
            finePrint
        } overview: { _ in
            header
            leagueHero
            membershipCard
        } controls: { _ in
            seasonPicker
            standings
            finePrint
        }
        .navigationTitle("Ashtray League")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            league.bind(repository: repository)
            await league.load()
        }
        .onChange(of: league.season) { _, _ in Task { await league.load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await league.load() } }
        }
        .confirmationDialog("Leave the Ashtray League?", isPresented: $confirmsLeaving, titleVisibility: .visible) {
            Button("Leave & delete league data", role: .destructive) {
                consentsToPublicProfile = false
                Task { await league.leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your public alias and saved league totals after the server confirms deletion. Your cigarette history stays on your devices.")
        }
        .accessibilityIdentifier("leaderboard-screen")
    }

    private var header: some View {
        CiggyScreenHeader("Global standings · weekly edition", title: "Ashtray League.",
                          subtitle: "The smoking section. Questionable bragging rights.")
    }

    private var leagueHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    heroCopy
                    LeaguePackPodium().frame(width: 116, height: 112)
                }
                VStack(alignment: .leading, spacing: 12) {
                    LeaguePackPodium().frame(width: 96, height: 88)
                    heroCopy
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("One global league")
                Spacer(minLength: 0)
                Text("Resets every Monday")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(palette.primaryText)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(palette.border).frame(height: 1) }
        }
        .padding(20)
        .background(palette.heroGradient, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(palette.border, lineWidth: 1))
    }

    private var heroCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The most logged.\nThe least subtle.")
                .font(.system(.title2, design: .rounded, weight: .black))
                .tracking(-0.6)
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Highest cigarette count wins. Management has approved absolutely no prizes.")
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var membershipCard: some View {
        if league.pendingDeletion {
            CiggyPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Leaving the league", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("Your deletion is pending. Your public record may remain visible until the server confirms it. Count sharing is paused.")
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                    actionButton("Retry deletion", systemImage: "arrow.clockwise", identifier: "league-retry-delete") {
                        await league.leave()
                    }
                }
                .foregroundStyle(palette.primaryText)
            }
        } else if league.isMember, let member = league.member {
            CiggyPanel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        CiggyProfileMark(size: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YOUR LEAGUE ALIAS").font(.caption2.weight(.heavy)).tracking(1.5)
                                .foregroundStyle(palette.secondaryText)
                            Text(member.alias).font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(palette.primaryText)
                                .accessibilityIdentifier("league-alias")
                        }
                        Spacer(minLength: 0)
                    }
                    if league.season == .current {
                        countProgress
                        actionButton("Sync my count", systemImage: "arrow.triangle.2.circlepath",
                                     identifier: "league-sync-count", disabled: !league.canSync) {
                            await league.synchronize()
                        }
                        if let message = league.scoreSyncMessage {
                            Text(message).font(.caption).foregroundStyle(palette.secondaryText)
                                .accessibilityIdentifier("league-score-sync-status")
                        }
                    } else {
                        Text("Looking back at last week. Switch to This week to sync your latest saved totals.")
                            .font(.subheadline).foregroundStyle(palette.secondaryText)
                    }
                    Button("Leave & delete league data", role: .destructive) { confirmsLeaving = true }
                        .font(.caption.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(league.isWorking || league.isLoading)
                        .accessibilityIdentifier("league-leave")
                }
            }
        } else {
            CiggyPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("An unofficial hall of ash.")
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(palette.primaryText)
                    Text("A fresh alias. A public spot on the board. Share this week’s and last week’s cigarette totals to join.")
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                    Toggle(isOn: $consentsToPublicProfile) {
                        Text("Share my alias and weekly cigarette totals publicly")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                    }
                    .tint(CiggyTheme.ember)
                    .disabled(league.isWorking || league.isLoading)
                    .accessibilityIdentifier("league-public-consent")
                    actionButton("Join the league", systemImage: "arrow.right", identifier: "league-join",
                                 disabled: !consentsToPublicProfile) {
                        await league.join()
                    }
                    Text("Optional. Leave and delete your league data whenever you like.")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    private var countProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(league.localWeeklyCount.map(String.init) ?? "—")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .monospacedDigit()
                Text("cigarettes logged this week").font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let me = league.board?.me, me.score != league.localWeeklyCount {
                Text("\(me.score) on the board · update pending").font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .foregroundStyle(palette.primaryText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("league-week-count")
    }

    private var seasonPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("League week", selection: $league.season) {
                Text("This week").tag(LeagueSeason.current)
                Text("Last week").tag(LeagueSeason.previous)
            }
            .pickerStyle(.segmented)
            .disabled(league.isWorking || league.isLoading)
            .accessibilityIdentifier("league-season")
            if let board = league.board {
                VStack(alignment: .leading, spacing: 4) {
                    Text(seasonDates(board)).font(.subheadline.weight(.bold))
                        .foregroundStyle(palette.primaryText)
                    Text(league.season == .current ? "Resets \(localDate(board.seasonEnd, includeTime: true))" : "Ended \(localDate(board.seasonEnd, includeTime: true))")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var standings: some View {
        status
        if let board = league.board {
            if let me = board.me {
                CiggyPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("YOUR STANDING").font(.caption2.weight(.heavy)).tracking(1.5)
                            .foregroundStyle(palette.secondaryText)
                        rankRow(me, isYou: true)
                        if me.rank == nil {
                            Text(me.updatedAt == nil ? "Your spot is reserved. Your count is waiting to sync." : "No cigarettes logged for this week.")
                                .font(.caption).foregroundStyle(palette.secondaryText)
                        }
                    }
                }
                .accessibilityIdentifier("league-your-standing")
            }
            CiggyPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("The roll call").font(.system(.title3, design: .rounded, weight: .black))
                        Spacer(minLength: 8)
                        Text("\(board.totalParticipants) \(board.totalParticipants == 1 ? "member" : "members")")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    .foregroundStyle(palette.primaryText)
                    if board.entries.isEmpty {
                        emptyStandings
                    } else {
                        if !dynamicTypeSize.isAccessibilitySize {
                            topMembers(board.entries)
                        }
                        ForEach(board.entries, id: \.id) { entry in
                            rankRow(entry, isYou: entry.id == league.member?.id)
                            if entry.id != board.entries.last?.id {
                                Divider().overlay(palette.border)
                            }
                        }
                        Text("Top 50 shown · Equal totals share a rank")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                }
            }
            .accessibilityIdentifier("league-standings")
        } else if league.isLoading {
            ProgressView("Fetching the roll call…")
                .frame(maxWidth: .infinity).padding(24)
                .foregroundStyle(palette.secondaryText)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let message = league.errorMessage {
            CiggyPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("League update paused", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.bold)).foregroundStyle(palette.primaryText)
                    Text(message).font(.caption).foregroundStyle(palette.secondaryText)
                    if let board = league.board {
                        Text("Saved standings from \(localDate(board.generatedAt, includeTime: true)).")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    Button("Try again") { Task { await league.load() } }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .disabled(league.isLoading || league.isWorking)
                        .accessibilityIdentifier("league-retry")
                }
            }
            .accessibilityIdentifier("league-error")
        } else if let board = league.board {
            HStack(alignment: .center, spacing: 10) {
                if league.isLoading { ProgressView().controlSize(.small) }
                Text("Updated \(localDate(board.generatedAt, includeTime: true))")
                    .font(.caption).foregroundStyle(palette.secondaryText)
                Spacer(minLength: 0)
                Button { Task { await league.load() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).foregroundStyle(palette.mint)
                .accessibilityLabel("Refresh league standings")
                .accessibilityHint("Recent saved standings are reused for up to one minute")
                .disabled(league.isLoading || league.isWorking)
                .accessibilityIdentifier("league-refresh")
            }
        }
    }

    private var emptyStandings: some View {
        VStack(alignment: .center, spacing: 10) {
            CiggyMascot(animated: false).frame(width: 88, height: 88)
            Text(league.season == .current ? "First chair is still open." : "A very quiet roll call.")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(palette.primaryText)
            Text(league.season == .current ? "No entries yet. The ashtray has been polished for the occasion." : "No cigarette totals were shared for this week.")
                .font(.subheadline).foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .accessibilityIdentifier("league-empty")
    }

    private func topMembers(_ entries: [LeagueEntry]) -> some View {
        let podium = entries.count >= 3 ? [entries[1], entries[0], entries[2]] : Array(entries.prefix(3))
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(podium, id: \.id) { entry in
                VStack(spacing: 6) {
                    Text(entry.rank.map { "#\($0)" } ?? "—")
                        .font(.system(.title2, design: .rounded, weight: .black))
                    Text(entry.alias).font(.caption2.weight(.bold))
                        .multilineTextAlignment(.center).lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: 38)
                    Text("\(entry.score) logged")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, entry.rank == 1 ? 24 : entry.rank == 2 ? 16 : 10)
                        .background(CiggyTheme.peach.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                }
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(palette.elevatedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
        // The complete accessible ranking immediately follows this visual summary.
        .accessibilityHidden(true)
    }

    private func rankRow(_ entry: LeagueEntry, isYou: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(entry.rank.map { "\($0)" } ?? "—")
                .font(.system(.headline, design: .rounded, weight: .black)).monospacedDigit()
                .frame(minWidth: 30)
                .foregroundStyle(isYou ? palette.mint : palette.primaryText)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.alias).font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.primaryText)
                if isYou { Text("You").font(.caption.weight(.semibold)).foregroundStyle(palette.mint) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.score)").font(.system(.title3, design: .rounded, weight: .black))
                    .monospacedDigit().foregroundStyle(palette.primaryText)
                Text("logged").font(.caption2).foregroundStyle(palette.secondaryText)
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.rank.map { "Rank \($0)" } ?? "Unranked"), \(entry.alias)\(isYou ? ", you" : ""), \(entry.score) cigarettes logged")
    }

    private var finePrint: some View {
        DisclosureGroup("League rules & privacy") {
            VStack(alignment: .leading, spacing: 8) {
            Text("Weeks run Monday–Sunday in UTC. Highest logged cigarette total ranks first. Equal totals share a rank. Corrections can lower your total, including last week’s.")
            Text("Counts include manual logs and automatic estimates. Watch updates and corrections can change standings.")
            Text("Only your generated alias, weekly cigarette totals, rank, and count-update time are public. Exact cigarette times, notes, motion, heart rate, and location stay private. Leave to delete your league profile and totals. See the privacy policy in Settings for retention details.")
            }
            .padding(.top, 8)
        }
        .font(.caption).foregroundStyle(palette.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4).padding(.bottom, 12)
        .accessibilityIdentifier("league-rules")
    }

    private func actionButton(_ title: String, systemImage: String, identifier: String,
                              disabled: Bool = false, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            HStack(spacing: 9) {
                if league.isWorking { ProgressView().tint(palette.primaryText) }
                Label(title, systemImage: systemImage)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.headline)
            .foregroundStyle(palette.primaryText)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 14).padding(.horizontal, 10)
            .background(CiggyTheme.peach.opacity(disabled ? 0.25 : 0.7), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled || league.isWorking || league.isLoading)
        .accessibilityIdentifier(identifier)
    }

    private func seasonDates(_ board: LeagueBoard) -> String {
        guard let start = parseDate(board.seasonStart), let end = parseDate(board.seasonEnd) else { return "Weekly standings" }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return "\(start.formatted(style)) – \(end.addingTimeInterval(-1).formatted(style)) · UTC"
    }

    private func localDate(_ value: String, includeTime: Bool = false) -> String {
        guard let date = parseDate(value) else { return "unavailable" }
        return date.formatted(date: .abbreviated, time: includeTime ? .shortened : .omitted)
    }

    private func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Three paper cigarettes form an intentionally ridiculous podium, not a score meter.
private struct LeaguePackPodium: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 116, size.height / 112)
            context.scaleBy(x: scale, y: scale)
            let ink = CiggyTheme.ink
            let columns: [(CGFloat, CGFloat, String)] = [(5, 54, "2"), (42, 28, "1"), (79, 68, "3")]
            for (x, y, rank) in columns {
                let body = Path(roundedRect: CGRect(x: x, y: y, width: 30, height: 104 - y), cornerRadius: 6)
                context.fill(body, with: .color(CiggyTheme.paper))
                context.stroke(body, with: .color(ink), lineWidth: 1.5)
                let filter = Path(roundedRect: CGRect(x: x + 1, y: 86, width: 28, height: 17), cornerRadius: 4)
                context.fill(filter, with: .color(CiggyTheme.peach))
                context.draw(Text(rank).font(.system(size: 17, weight: .black, design: .rounded)).foregroundColor(ink),
                             at: CGPoint(x: x + 15, y: y + 16))
                var seam = Path()
                seam.move(to: CGPoint(x: x + 1, y: 85))
                seam.addLine(to: CGPoint(x: x + 29, y: 85))
                context.stroke(seam, with: .color(ink.opacity(0.4)), lineWidth: 1)
            }
            var crown = Path()
            crown.move(to: CGPoint(x: 43, y: 19))
            crown.addLines([CGPoint(x: 40, y: 7), CGPoint(x: 50, y: 12), CGPoint(x: 57, y: 2),
                           CGPoint(x: 64, y: 12), CGPoint(x: 74, y: 7), CGPoint(x: 71, y: 19)])
            crown.closeSubpath()
            context.fill(crown, with: .color(CiggyTheme.sunlight))
            context.stroke(crown, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .rotationEffect(.degrees(-5))
    }
}
#endif
