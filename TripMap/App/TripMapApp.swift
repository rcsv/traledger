import SwiftData
import SwiftUI

@main
struct TripMapApp: App {
    private let modelContainer: ModelContainer?
    private let storeErrorMessage: String?
    #if os(macOS)
    @StateObject private var commandRouter = MacCommandRouter()
    #endif

    init() {
        do {
            let container = try TripMapStore.makeContainer()
            #if TRIPMAP_QA
            if ProcessInfo.processInfo.arguments.contains("-tripmap-seed-venue-image-qa") {
                try DebugFixtureSeeder.seedVenueImageTripIfNeeded(in: container)
            }
            #endif
            modelContainer = container
            storeErrorMessage = nil
        } catch {
            modelContainer = nil
            storeErrorMessage = error.localizedDescription
        }
    }

    var body: some Scene {
        #if os(macOS)
        Window("TripMap", id: "library") {
            if let modelContainer {
                MacLibraryRootView()
                    .modelContainer(modelContainer)
                    .environmentObject(commandRouter)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
        }
        .commands {
            MacAppCommands(commandRouter: commandRouter)
        }

        WindowGroup(id: "trip", for: UUID.self) { $tripID in
            if let modelContainer {
                MacTripWorkspaceView(tripID: tripID)
                    .modelContainer(modelContainer)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
        }
        .commands {
            MacAppCommands(commandRouter: commandRouter)
        }

        Settings {
            if let modelContainer {
                TripMapSettingsView()
                    .modelContainer(modelContainer)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
        }
        #else
        WindowGroup {
            if let modelContainer {
                RootView()
                    .modelContainer(modelContainer)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
        }
        #endif
    }
}

#if os(macOS)
private struct MacAppCommands: Commands {
    @ObservedObject var commandRouter: MacCommandRouter
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.macTripCommandActions) private var tripActions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新しい Trip") {
                sendToLibrary(.createTrip)
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Activityを追加") {
                tripActions?.createActivity()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(tripActions?.canCreateActivity != true)
        }

        CommandGroup(after: .newItem) {
            Button("Participantを登録") {
                sendToLibrary(.registerParticipant)
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
        }

        CommandMenu("Trip") {
            Button("Activityを追加") {
                tripActions?.createActivity()
            }
            .disabled(tripActions?.canCreateActivity != true)

            Button("Activityを編集") {
                tripActions?.editActivity()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(tripActions?.canEditActivity != true)

            Divider()

            Button("日程を変更") {
                tripActions?.changeDateRange()
            }
            .disabled(tripActions == nil)

            Button("Participantを割り当て") {
                tripActions?.assignParticipant()
            }
            .disabled(tripActions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Library Windowを表示") {
                sendToLibrary(.showLibrary)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
        }
    }

    private func sendToLibrary(_ kind: MacLibraryCommandKind) {
        commandRouter.sendToLibrary(kind)
        openWindow(id: "library")
    }
}
#endif

#if TRIPMAP_QA
@MainActor
private enum DebugFixtureSeeder {
    static func seedVenueImageTripIfNeeded(in container: ModelContainer) throws {
        var fixture = VenueImageQAFixture.trip
        if ProcessInfo.processInfo.arguments.contains("-tripmap-venue-image-qa-preseed-user-image"),
           let activityIndex = fixture.days[0].activities.firstIndex(
               where: { $0.id == VenueImageQAFixture.userImageActivityID }
           ) {
            fixture.days[0].activities[activityIndex].place?.imageData =
                VenueImageQAFixture.preseededUserImageData
        }
        if ProcessInfo.processInfo.arguments.contains("-tripmap-activity-progress-qa") {
            fixture.days[0].activities[0].progress = .completed
            fixture.days[0].activities[0].progressUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
            fixture.days[0].activities[1].progress = .skipped
            fixture.days[0].activities[1].progressUpdatedAt = Date(timeIntervalSince1970: 1_800_000_060)
        }
        if ProcessInfo.processInfo.arguments.contains("-tripmap-travel-leg-preference-qa"),
           let legID = TravelLegProjection.activeLegs(for: fixture).first?.id {
            fixture.travelLegPreferences = [
                TravelLegPreference(
                    legID: legID,
                    transportType: .transit,
                    manualDurationMinutes: 42,
                    note: "駅で乗り換え"
                )
            ]
        }

        let fixtureID = fixture.id
        let descriptor = FetchDescriptor<StoredTrip>(
            predicate: #Predicate<StoredTrip> { $0.id == fixtureID }
        )
        if let storedTrip = try container.mainContext.fetch(descriptor).first {
            try storedTrip.applyPlan(fixture, in: container.mainContext)
        } else {
            container.mainContext.insert(
                try StoredTrip(validatingSnapshot: fixture)
            )
        }
        try container.mainContext.save()
    }
}
#endif

private struct StoreUnavailableView: View {
    let message: String?

    var body: some View {
        ContentUnavailableView(
            "旅行データを開けません",
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text("TripMapを再起動してください。問題が続く場合は、データを消去せずにサポートへ連絡してください。\n\n\(message ?? "不明な保存領域エラー")")
        )
    }
}
