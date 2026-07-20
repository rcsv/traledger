import SwiftData
import SwiftUI

#if os(iOS)
struct MobileAppShellView: View {
    var body: some View {
        TabView {
            TripsTabView()
                .tabItem {
                    Label("Trips", systemImage: "suitcase.rolling")
                }
            NavigationStack {
                ParticipantsView()
            }
            .tabItem {
                Label("People", systemImage: "person.2")
            }
            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Me", systemImage: "person.crop.circle")
            }
        }
    }
}

private struct TripsTabView: View {
    @State private var scope: TripLibraryScope = .upcoming
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            TripLibraryHomeView(
                scope: $scope,
                showsScopePicker: true,
                onOpenTrip: { path.append($0) }
            )
            .navigationDestination(for: UUID.self) { tripID in
                TripGuideWorkspaceView(tripID: tripID)
            }
        }
    }
}

private struct TripGuideWorkspaceView: View {
    @Query private var storedTrips: [StoredTrip]

    init(tripID: UUID) {
        _storedTrips = Query(filter: #Predicate<StoredTrip> { $0.id == tripID })
    }

    var body: some View {
        if let trip = storedTrips.first?.snapshot {
            GuideView(trip: trip)
                .id(trip.id)
        } else {
            ContentUnavailableView(
                "旅行データを読み込めません",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("旅行一覧へ戻って別のTripを選んでください。")
            )
        }
    }
}
#endif

#if os(macOS)
private enum MacLibraryDestination: Hashable {
    case trips(TripLibraryScope)
    case people
    case profile
}

struct MacLibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var destination: MacLibraryDestination? = .trips(.upcoming)

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("Trips") {
                    Label("Upcoming", systemImage: "calendar.badge.clock")
                        .tag(MacLibraryDestination.trips(.upcoming))
                    Label("Past", systemImage: "clock.arrow.circlepath")
                        .tag(MacLibraryDestination.trips(.past))
                    Label("すべて", systemImage: "tray.full")
                        .tag(MacLibraryDestination.trips(.all))
                }
                Section("People") {
                    Label("Participants", systemImage: "person.2")
                        .tag(MacLibraryDestination.people)
                }
                Section("Account") {
                    Label("Me", systemImage: "person.crop.circle")
                        .tag(MacLibraryDestination.profile)
                }
            }
            .navigationTitle("TripMap")
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination ?? .trips(.upcoming) {
        case .trips:
            NavigationStack {
                TripLibraryHomeView(
                    scope: tripScopeBinding,
                    showsScopePicker: false,
                    onOpenTrip: { openWindow(id: "trip", value: $0) },
                    onDeleteTrip: { dismissWindow(id: "trip", value: $0) }
                )
            }
        case .people:
            NavigationStack { ParticipantsView() }
        case .profile:
            NavigationStack { ProfileView() }
        }
    }

    private var tripScopeBinding: Binding<TripLibraryScope> {
        Binding(
            get: {
                if case .trips(let scope) = destination { return scope }
                return .upcoming
            },
            set: { destination = .trips($0) }
        )
    }
}

struct MacTripWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedTrips: [StoredTrip]

    init(tripID: UUID?) {
        if let tripID {
            _storedTrips = Query(filter: #Predicate<StoredTrip> { $0.id == tripID })
        } else {
            _storedTrips = Query()
        }
    }

    var body: some View {
        if let trip = storedTrips.first?.snapshot {
            PlanView(trip: trip, onApplyPlan: { updated in
                guard let storedTrip = storedTrips.first else { return "旅行データを読み込めませんでした。" }
                do {
                    try storedTrip.applyPlan(updated, in: modelContext)
                    try modelContext.save()
                    return nil
                } catch {
                    modelContext.rollback()
                    return error.localizedDescription
                }
            })
                .id(trip.id)
        } else {
            ContentUnavailableView(
                "旅行を開けません",
                systemImage: "suitcase.rolling",
                description: Text("Libraryウィンドウから旅行を選んでください。")
            )
        }
    }
}

struct TripMapSettingsView: View {
    var body: some View {
        TabView {
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            VStack(alignment: .leading, spacing: 12) {
                Text("一般")
                    .font(.headline)
                Text("地図表示、同期、バックアップの設定は後続のマイルストーンで追加します。")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .tabItem { Label("一般", systemImage: "gear") }
        }
        .frame(width: 420, height: 280)
    }
}
#endif
