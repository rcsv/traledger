import Foundation
import MapKit

enum VenueImageSource: Equatable {
    case loading
    case user
    case lookAround
    case wikimedia
    case placeholder
}

struct VenueImageResolutionRequestID: Hashable {
    let placeID: UUID
    let hasUserImage: Bool
}

enum VenueImageResolution<LookAround> {
    case user
    case lookAround(LookAround)
    case wikimedia(ExternalPlaceImage)
    case placeholder

    var source: VenueImageSource {
        switch self {
        case .user: .user
        case .lookAround: .lookAround
        case .wikimedia: .wikimedia
        case .placeholder: .placeholder
        }
    }
}

/// Chooses the image source without depending on MapKit or Wikimedia networking.
/// The closures make each branch deterministic in tests and preserve the product priority.
@MainActor
enum VenueImageResolutionCoordinator {
    static func resolve<LookAround>(
        hasUserImage: Bool,
        existingExternalImage: ExternalPlaceImage?,
        resolveLookAround: () async -> LookAround?,
        resolveWikimedia: () async -> ExternalPlaceImage?
    ) async -> VenueImageResolution<LookAround> {
        guard !hasUserImage else { return .user }

        if let scene = await resolveLookAround() {
            return .lookAround(scene)
        }

        guard !Task.isCancelled else { return .placeholder }

        if let existingExternalImage {
            return .wikimedia(existingExternalImage)
        }

        if let image = await resolveWikimedia() {
            return .wikimedia(image)
        }

        return .placeholder
    }
}

@MainActor
struct VenueImageResolutionDependencies {
    var resolveLookAround: (PlaceSnapshot) async -> MKLookAroundScene?
    var resolveWikimedia: (PlaceSnapshot) async -> ExternalPlaceImage?

    static let live = VenueImageResolutionDependencies(
        resolveLookAround: { place in
            let request = MKLookAroundSceneRequest(coordinate: place.coordinate)
            return try? await request.scene
        },
        resolveWikimedia: { place in
            await WikimediaImageResolver.resolveExactVenueImage(for: place)
        }
    )
}

/// Owns the automatic image request for the lifetime of a Venue Card.
/// SwiftUI may recreate the card's `body` while MapKit is settling, so the
/// networking task deliberately lives here rather than in a view `.task`.
@MainActor
final class VenueImageResolutionModel: ObservableObject {
    @Published private(set) var source: VenueImageSource = .placeholder
    @Published private(set) var lookAroundScene: MKLookAroundScene?
    @Published private(set) var externalImage: ExternalPlaceImage?

    private let dependencies: VenueImageResolutionDependencies
    private var activeRequestID: VenueImageResolutionRequestID?
    private var resolutionTask: Task<Void, Never>?

    init(dependencies: VenueImageResolutionDependencies = .live) {
        self.dependencies = dependencies
    }

    func load(
        _ place: PlaceSnapshot,
        onWikimediaImage: @escaping (ExternalPlaceImage) -> Void
    ) {
        let requestID = VenueImageResolutionRequestID(
            placeID: place.id,
            hasUserImage: place.imageData != nil
        )
        guard requestID != activeRequestID else { return }

        resolutionTask?.cancel()
        activeRequestID = requestID
        lookAroundScene = nil
        externalImage = place.externalImage
        source = place.imageData == nil ? .loading : .user

        resolutionTask = Task { [weak self] in
            let resolution = await VenueImageResolutionCoordinator.resolve(
                hasUserImage: place.imageData != nil,
                existingExternalImage: place.externalImage,
                resolveLookAround: {
                    await self?.dependencies.resolveLookAround(place)
                },
                resolveWikimedia: {
                    await self?.dependencies.resolveWikimedia(place)
                }
            )

            guard let self, !Task.isCancelled, self.activeRequestID == requestID else { return }

            self.source = resolution.source
            switch resolution {
            case let .lookAround(scene):
                self.lookAroundScene = scene
            case let .wikimedia(image):
                self.externalImage = image
                if place.externalImage == nil {
                    onWikimediaImage(image)
                }
            case .user, .placeholder:
                break
            }
        }
    }

    func cancel() {
        resolutionTask?.cancel()
        resolutionTask = nil
        activeRequestID = nil
    }

    /// Test seam for deterministic lifecycle verification. Production views
    /// never need to wait for an external image before presenting Venue text.
    func awaitCurrentResolution() async {
        await resolutionTask?.value
    }
}
