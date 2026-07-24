import AppIntents
import SwiftData

struct CheckNextActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "次の予定を確認"
    static let description = IntentDescription(
        "今日の進行中または次の予定を、TripMapを開かずに確認します。"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            guard let summary = try TripSystemExperienceReader.currentSummary() else {
                return .result(dialog: "今日の進行中または次の予定はありません。")
            }
            return .result(dialog: "\(summary.spokenSummary)")
        } catch {
            return .result(
                dialog: "旅行データを安全に読み込めませんでした。TripMapを開いて確認してください。"
            )
        }
    }
}

struct TripMapAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckNextActivityIntent(),
            phrases: [
                "\(.applicationName)で次の予定を確認",
                "\(.applicationName)の次の予定"
            ],
            shortTitle: "次の予定",
            systemImageName: "calendar.badge.clock"
        )
    }

    static var shortcutTileColor: ShortcutTileColor {
        .blue
    }
}

@MainActor
enum TripSystemExperienceReader {
    static func currentSummary(
        now: Date = Date()
    ) throws -> TripSystemExperienceSummary? {
        let container = try TripMapStore.makeContainer()
        let storedTrips = try container.mainContext.fetch(FetchDescriptor<StoredTrip>())
        let trips = storedTrips.compactMap(\.snapshot)
        return TripSystemExperienceProjection.currentSummary(for: trips, now: now)
    }
}
