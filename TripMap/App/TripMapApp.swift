import SwiftData
import SwiftUI

@main
struct TripMapApp: App {
    private let modelContainer: ModelContainer?
    private let storeErrorMessage: String?

    init() {
        do {
            modelContainer = try TripMapStore.makeContainer()
            storeErrorMessage = nil
        } catch {
            modelContainer = nil
            storeErrorMessage = error.localizedDescription
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            if let modelContainer {
                MacLibraryRootView()
                    .modelContainer(modelContainer)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
        }

        WindowGroup(id: "trip", for: UUID.self) { $tripID in
            if let modelContainer {
                MacTripWorkspaceView(tripID: tripID)
                    .modelContainer(modelContainer)
            } else {
                StoreUnavailableView(message: storeErrorMessage)
            }
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
