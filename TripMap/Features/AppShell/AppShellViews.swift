import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#endif

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
    #if TRIPMAP_QA
    @State private var didOpenVenueImageQA = false
    #endif

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
        #if TRIPMAP_QA
        .task {
            guard !didOpenVenueImageQA,
                  ProcessInfo.processInfo.arguments.contains("-tripmap-open-venue-image-qa") else {
                return
            }
            didOpenVenueImageQA = true
            path = [VenueImageQAFixture.tripID]
        }
        #endif
    }
}

private struct TripGuideWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var storedTrips: [StoredTrip]

    init(tripID: UUID) {
        _storedTrips = Query(filter: #Predicate<StoredTrip> { $0.id == tripID })
    }

    var body: some View {
        if let trip = storedTrips.first?.snapshot {
            GuideView(
                trip: trip,
                initialActivityID: venueImageQAInitialActivityID,
                onApplyPlan: TripPersistenceBoundary.rejectBroadPlanWrite,
                onApplyMutation: { mutation in
                    guard let storedTrip = storedTrips.first else {
                        return "旅行データを読み込めませんでした。"
                    }
                    do {
                        try storedTrip.applyMutation(mutation, in: modelContext)
                        try modelContext.save()
                        if case .recordActivityMemory = mutation,
                           let updated = storedTrip.snapshot {
                            Task {
                                try? await GuideReminderScheduler.sync(
                                    trip: updated,
                                    requestingAuthorization: false
                                )
                            }
                        }
                        return nil
                    } catch {
                        modelContext.rollback()
                        return error.localizedDescription
                    }
                }
            )
                .id(trip.id)
        } else {
            ContentUnavailableView(
                "旅行データを読み込めません",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text("旅行一覧へ戻って別のTripを選んでください。")
            )
        }
    }

    private var venueImageQAInitialActivityID: Activity.ID? {
        #if TRIPMAP_QA
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-tripmap-open-venue-image-qa") else {
            return nil
        }
        if arguments.contains("-tripmap-venue-image-qa-wikimedia") {
            return VenueImageQAFixture.wikimediaActivityID
        }
        if arguments.contains("-tripmap-venue-image-qa-user") {
            return VenueImageQAFixture.userImageActivityID
        }
        return VenueImageQAFixture.lookAroundActivityID
        #else
        return nil
        #endif
    }
}
#endif

#if os(macOS)
enum MacLibraryCommandKind: Equatable, Sendable {
    case showLibrary
    case createTrip
    case registerParticipant
}

struct MacLibraryCommandRequest: Equatable, Sendable {
    let id: UUID
    let kind: MacLibraryCommandKind
}

@MainActor
final class MacCommandRouter: ObservableObject {
    @Published private(set) var libraryRequest: MacLibraryCommandRequest?

    func sendToLibrary(_ kind: MacLibraryCommandKind) {
        libraryRequest = MacLibraryCommandRequest(id: UUID(), kind: kind)
    }
}

struct MacTripCommandActions {
    let canCreateActivity: Bool
    let canEditActivity: Bool
    let createActivity: () -> Void
    let editActivity: () -> Void
    let changeDateRange: () -> Void
    let assignParticipant: () -> Void
}

private struct MacTripCommandActionsKey: FocusedValueKey {
    typealias Value = MacTripCommandActions
}

extension FocusedValues {
    var macTripCommandActions: MacTripCommandActions? {
        get { self[MacTripCommandActionsKey.self] }
        set { self[MacTripCommandActionsKey.self] = newValue }
    }
}

private enum MacLibraryDestination: Hashable {
    case dashboard
    case trips(TripLibraryScope)
    case people
    case profile
}

struct MacLibraryRootView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var commandRouter: MacCommandRouter
    @State private var destination: MacLibraryDestination? = .trips(.upcoming)
    @State private var newTripRequestID: UUID?
    @State private var newParticipantRequestID: UUID?
    @State private var handledCommandID: UUID?
    #if TRIPMAP_QA
    @State private var didOpenVenueImageQA = false
    #endif

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("Overview") {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                        .tag(MacLibraryDestination.dashboard)
                }
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
        .onAppear {
            handleLibraryCommand(commandRouter.libraryRequest)
        }
        .onChange(of: commandRouter.libraryRequest) { _, request in
            handleLibraryCommand(request)
        }
        #if TRIPMAP_QA
        .task {
            guard !didOpenVenueImageQA,
                  ProcessInfo.processInfo.arguments.contains("-tripmap-open-venue-image-qa") else {
                return
            }
            didOpenVenueImageQA = true
            openWindow(id: "trip", value: VenueImageQAFixture.trip.id)
        }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination ?? .trips(.upcoming) {
        case .dashboard:
            NavigationStack {
                LibraryDashboardView(
                    onOpenTrip: { openWindow(id: "trip", value: $0) }
                )
            }
        case .trips:
            NavigationStack {
                TripLibraryHomeView(
                    scope: tripScopeBinding,
                    showsScopePicker: false,
                    creationRequestID: newTripRequestID,
                    onOpenTrip: { openWindow(id: "trip", value: $0) },
                    onDeleteTrip: { dismissWindow(id: "trip", value: $0) }
                )
            }
        case .people:
            NavigationStack {
                ParticipantsView(
                    creationRequestID: newParticipantRequestID
                )
            }
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

    private func handleLibraryCommand(
        _ request: MacLibraryCommandRequest?
    ) {
        guard let request, request.id != handledCommandID else { return }
        handledCommandID = request.id
        switch request.kind {
        case .showLibrary:
            break
        case .createTrip:
            destination = .trips(.upcoming)
            newTripRequestID = request.id
        case .registerParticipant:
            destination = .people
            newParticipantRequestID = request.id
        }
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
            PlanView(
                trip: trip,
                initialDayID: venueImageQAInitialDayID,
                initialActivityID: venueImageQAInitialActivityID,
                onApplyPlan: TripPersistenceBoundary.rejectBroadPlanWrite,
                onApplyMutation: { mutation in
                    guard let storedTrip = storedTrips.first else { return "旅行データを読み込めませんでした。" }
                    do {
                        try storedTrip.applyMutation(mutation, in: modelContext)
                        try modelContext.save()
                        return nil
                    } catch {
                        modelContext.rollback()
                        return error.localizedDescription
                    }
                }
            )
            .id(trip.id)
            .task {
                await foregroundVenueImageQAWindowIfNeeded()
            }
        } else {
            ContentUnavailableView(
                "旅行を開けません",
                systemImage: "suitcase.rolling",
                description: Text("Libraryウィンドウから旅行を選んでください。")
            )
        }
    }

    private var venueImageQAInitialDayID: Day.ID? {
        #if TRIPMAP_QA
        guard ProcessInfo.processInfo.arguments.contains("-tripmap-open-venue-image-qa") else {
            return nil
        }
        return VenueImageQAFixture.trip.orderedDays.first?.id
        #else
        return nil
        #endif
    }

    private var venueImageQAInitialActivityID: Activity.ID? {
        #if TRIPMAP_QA
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-tripmap-open-venue-image-qa") else {
            return nil
        }
        if arguments.contains("-tripmap-venue-image-qa-wikimedia") {
            return VenueImageQAFixture.wikimediaActivityID
        }
        if arguments.contains("-tripmap-venue-image-qa-user") {
            return VenueImageQAFixture.userImageActivityID
        }
        return VenueImageQAFixture.lookAroundActivityID
        #else
        return nil
        #endif
    }

    @MainActor
    private func foregroundVenueImageQAWindowIfNeeded() async {
        #if TRIPMAP_QA
        guard ProcessInfo.processInfo.arguments.contains("-tripmap-open-venue-image-qa") else {
            return
        }
        await Task.yield()
        NSApplication.shared.activate()
        for window in NSApplication.shared.windows where window.title == VenueImageQAFixture.trip.title {
            if ProcessInfo.processInfo.arguments.contains("-tripmap-venue-image-qa-narrow") {
                window.setContentSize(NSSize(width: 700, height: 720))
            } else if ProcessInfo.processInfo.arguments.contains("-tripmap-venue-image-qa-regular") {
                window.setContentSize(NSSize(width: 1180, height: 720))
            }
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
        }
        #endif
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
