import Foundation

/// Resolves a photo only when a Venue has an exact Wikipedia article title and
/// the corresponding Commons file supplies the attribution required to show it.
/// Nearby or fuzzy matches deliberately fall through to the next image source.
enum WikimediaImageResolver {
    static func resolveExactVenueImage(for place: PlaceSnapshot) async -> ExternalPlaceImage? {
        guard let pageImage = try? await wikipediaPageImage(named: place.name),
              let image = try? await commonsImage(named: pageImage) else {
            return nil
        }
        return image
    }

    private static func wikipediaPageImage(named title: String) async throws -> String? {
        let response: WikipediaResponse = try await request(
            host: "ja.wikipedia.org",
            items: [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "formatversion", value: "2"),
                URLQueryItem(name: "titles", value: title),
                URLQueryItem(name: "prop", value: "pageimages"),
                URLQueryItem(name: "piprop", value: "thumbnail|name"),
                URLQueryItem(name: "pithumbsize", value: "640")
            ]
        )

        guard let page = response.query?.pages?.first,
              page.missing != true,
              normalized(page.title) == normalized(title) else {
            return nil
        }
        return page.pageImage
    }

    private static func commonsImage(named filename: String) async throws -> ExternalPlaceImage? {
        let response: CommonsResponse = try await request(
            host: "commons.wikimedia.org",
            items: [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "formatversion", value: "2"),
                URLQueryItem(name: "titles", value: "File:\(filename)"),
                URLQueryItem(name: "prop", value: "imageinfo"),
                URLQueryItem(name: "iiprop", value: "url|extmetadata"),
                URLQueryItem(name: "iiurlwidth", value: "640"),
                URLQueryItem(name: "iiextmetadatafilter", value: "Artist|LicenseShortName|LicenseUrl")
            ]
        )

        guard let page = response.query?.pages?.first,
              let info = page.imageInfo?.first,
              let thumbnailURL = info.thumbnailURL.flatMap(URL.init(string:)),
              let sourcePageURL = info.descriptionURL.flatMap(URL.init(string:)),
              let metadata = info.extMetadata,
              let authorHTML = metadata["Artist"]?.value,
              let licenseNameHTML = metadata["LicenseShortName"]?.value,
              let licenseURLString = metadata["LicenseUrl"]?.value,
              let licenseURL = URL(string: licenseURLString) else {
            return nil
        }
        let author = plainText(authorHTML)
        let licenseName = plainText(licenseNameHTML)
        guard !author.isEmpty, !licenseName.isEmpty else { return nil }

        return ExternalPlaceImage(
            provider: .wikimediaCommons,
            providerImageID: page.title,
            imageURL: thumbnailURL,
            sourcePageURL: sourcePageURL,
            authorName: author,
            authorURL: firstLink(in: authorHTML),
            licenseName: licenseName,
            licenseURL: licenseURL,
            kind: .exactVenue,
            fetchedAt: .now
        )
    }

    private static func request<Response: Decodable>(
        host: String,
        items: [URLQueryItem]
    ) async throws -> Response {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/w/api.php"
        components.queryItems = items
        guard let url = components.url else { throw WikimediaError.invalidRequest }

        var request = URLRequest(url: url)
        request.setValue("TripMap/1.0 Wikimedia image resolver", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WikimediaError.invalidResponse
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
    }

    private static func plainText(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstLink(in html: String) -> URL? {
        guard let match = html.range(of: "href=\\\"([^\\\"]+)\\\"", options: .regularExpression) else {
            return nil
        }
        let attribute = String(html[match])
        let urlString = attribute
            .replacingOccurrences(of: "href=\"", with: "")
            .dropLast()
        return URL(string: String(urlString))
    }
}

private enum WikimediaError: Error {
    case invalidRequest
    case invalidResponse
}

private struct WikipediaResponse: Decodable {
    let query: WikipediaQuery?
}

private struct WikipediaQuery: Decodable {
    let pages: [WikipediaPage]?
}

private struct WikipediaPage: Decodable {
    let title: String
    let missing: Bool?
    let pageImage: String?

    enum CodingKeys: String, CodingKey {
        case title
        case missing
        case pageImage = "pageimage"
    }
}

private struct CommonsResponse: Decodable {
    let query: CommonsQuery?
}

private struct CommonsQuery: Decodable {
    let pages: [CommonsPage]?
}

private struct CommonsPage: Decodable {
    let title: String
    let imageInfo: [CommonsImageInfo]?

    enum CodingKeys: String, CodingKey {
        case title
        case imageInfo = "imageinfo"
    }
}

private struct CommonsImageInfo: Decodable {
    let thumbnailURL: String?
    let descriptionURL: String?
    let extMetadata: [String: CommonsMetadata]?

    enum CodingKeys: String, CodingKey {
        case thumbnailURL = "thumburl"
        case descriptionURL = "descriptionurl"
        case extMetadata = "extmetadata"
    }
}

private struct CommonsMetadata: Decodable {
    let value: String
}
