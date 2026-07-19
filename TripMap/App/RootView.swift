import SwiftUI

struct RootView: View {
    let trip: Trip

    var body: some View {
        #if os(macOS)
        PlanView(trip: trip)
        #else
        GuideView(trip: trip)
        #endif
    }
}
