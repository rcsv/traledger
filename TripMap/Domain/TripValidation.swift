import Foundation

enum TripValidationIssue: Equatable, Sendable {
    case noDays
    case invalidDaySequence
    case dayOutsideTripRange(Day.ID)
    case duplicateDayDate(Day.ID)
    case invalidActivitySequence(Day.ID)
    case invalidCoordinate(Activity.ID)
}

extension Trip {
    var orderedDays: [Day] {
        days.enumerated()
            .sorted {
                if $0.element.sequence == $1.element.sequence {
                    return $0.offset < $1.offset
                }
                return $0.element.sequence < $1.element.sequence
            }
            .map(\.element)
    }

    var validationIssues: [TripValidationIssue] {
        var issues: [TripValidationIssue] = []

        if days.isEmpty {
            issues.append(.noDays)
        }

        if orderedDays.map(\.sequence) != days.indices.map({ $0 + 1 }) {
            issues.append(.invalidDaySequence)
        }

        var seenDates: Set<Date> = []
        for day in days {
            if !dateRange.contains(day.date) {
                issues.append(.dayOutsideTripRange(day.id))
            }
            if !seenDates.insert(day.date).inserted {
                issues.append(.duplicateDayDate(day.id))
            }
            if day.orderedActivities.map(\.sequence) != day.activities.indices.map({ $0 + 1 }) {
                issues.append(.invalidActivitySequence(day.id))
            }
            for activity in day.activities {
                guard let place = activity.place else { continue }
                if !place.latitude.isFinite
                    || !place.longitude.isFinite
                    || !(-90...90).contains(place.latitude)
                    || !(-180...180).contains(place.longitude) {
                    issues.append(.invalidCoordinate(activity.id))
                }
            }
        }

        return issues
    }
}

extension Day {
    var orderedActivities: [Activity] {
        activities.enumerated()
            .sorted {
                if $0.element.sequence == $1.element.sequence {
                    return $0.offset < $1.offset
                }
                return $0.element.sequence < $1.element.sequence
            }
            .map(\.element)
    }
}
