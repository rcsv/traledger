import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedTrips: [StoredTrip]
    @State private var seedError: String?

    var body: some View {
        Group {
            if let trip = storedTrips.first?.snapshot {
                #if os(macOS)
                PlanView(trip: trip)
                #else
                GuideView(trip: trip)
                #endif
            } else if let seedError {
                ContentUnavailableView(
                    "旅行データを読み込めません",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(seedError)
                )
            } else {
                ProgressView("旅行を準備しています…")
            }
        }
        .task { seedSampleIfNeeded() }
    }

    private func seedSampleIfNeeded() {
        guard storedTrips.isEmpty, seedError == nil else { return }
        modelContext.insert(StoredTrip(snapshot: OkinawaSample.trip))
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            seedError = error.localizedDescription
        }
    }
}
