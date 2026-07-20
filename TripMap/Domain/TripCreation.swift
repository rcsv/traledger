import Foundation

struct TripCreationRequest: Equatable, Sendable {
    var title: String
    var startDate: LocalDate
    var endDate: LocalDate
    var timeZoneIdentifier: String
    var defaultCurrencyCode: String = "JPY"
}

enum TripCreationError: LocalizedError, Equatable, Sendable {
    case blankTitle
    case invalidTimeZone
    case endBeforeStart
    case dateOutsideSupportedRange
    case tooManyDays(maximum: Int)

    var errorDescription: String? {
        switch self {
        case .blankTitle:
            "旅行名を入力してください。"
        case .invalidTimeZone:
            "タイムゾーンを確認してください。"
        case .endBeforeStart:
            "終了日は開始日以降にしてください。"
        case .dateOutsideSupportedRange:
            "指定された日付を扱えません。"
        case .tooManyDays(let maximum):
            "旅行期間は最大\(maximum)日です。"
        }
    }
}

enum TripFactory {
    static let maximumDayCount = 366

    static func makeTrip(from request: TripCreationRequest, id: UUID = UUID()) throws -> Trip {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw TripCreationError.blankTitle }
        guard let timeZone = TimeZone(identifier: request.timeZoneIdentifier) else {
            throw TripCreationError.invalidTimeZone
        }
        guard request.startDate.code <= request.endDate.code else {
            throw TripCreationError.endBeforeStart
        }
        guard let startDate = request.startDate.date(in: timeZone),
              let endDate = request.endDate.date(in: timeZone) else {
            throw TripCreationError.dateOutsideSupportedRange
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var days: [Day] = []
        var date = startDate

        while date <= endDate {
            guard days.count < maximumDayCount else {
                throw TripCreationError.tooManyDays(maximum: maximumDayCount)
            }
            days.append(
                Day(
                    id: UUID(),
                    sequence: days.count + 1,
                    date: date,
                    title: "",
                    activities: []
                )
            )
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                throw TripCreationError.dateOutsideSupportedRange
            }
            date = nextDate
        }

        return Trip(
            id: id,
            title: title,
            dateRange: startDate...endDate,
            timeZoneIdentifier: timeZone.identifier,
            defaultCurrencyCode: request.defaultCurrencyCode,
            days: days
        )
    }
}
