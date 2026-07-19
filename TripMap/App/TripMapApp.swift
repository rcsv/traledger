import SwiftData
import SwiftUI

@main
struct TripMapApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try TripMapStore.makeContainer()
        } catch {
            fatalError("Unable to create TripMap store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
