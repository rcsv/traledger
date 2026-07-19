import SwiftUI

@main
struct TripMapApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(trip: OkinawaSample.trip)
        }
    }
}
