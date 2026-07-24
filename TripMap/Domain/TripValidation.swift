import Foundation

enum TripValidationIssue: Equatable, Sendable {
    case noDays
    case invalidDaySequence
    case dayOutsideTripRange(Day.ID)
    case duplicateDayDate(Day.ID)
    case invalidActivitySequence(Day.ID)
    case invalidActivityDuration(Activity.ID)
    case invalidActivityProgress(Activity.ID)
    case invalidReservationReference(Activity.ID)
    case invalidCoordinate(Activity.ID)
    case invalidTravelLegPreference(TravelLegID)
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
        var dayIDByActivityID: [Activity.ID: Day.ID] = [:]
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
                dayIDByActivityID[activity.id] = day.id
                if let durationMinutes = activity.durationMinutes,
                   !(1...1_440).contains(durationMinutes) {
                    issues.append(.invalidActivityDuration(activity.id))
                }
                if (activity.progress == .planned) != (activity.progressUpdatedAt == nil) {
                    issues.append(.invalidActivityProgress(activity.id))
                }
                if let reservation = activity.reservation {
                    let title = reservation.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let code = reservation.confirmationCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let note = reservation.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hasValidURL = reservation.url.map {
                        $0.scheme?.lowercased() == "https" && $0.host != nil
                    } ?? true
                    if title.isEmpty
                        || title != reservation.title
                        || (reservation.confirmationCode != nil && (code?.isEmpty != false || code != reservation.confirmationCode))
                        || (reservation.note != nil && (note?.isEmpty != false || note != reservation.note))
                        || !hasValidURL {
                        issues.append(.invalidReservationReference(activity.id))
                    }
                }
                guard let place = activity.place else { continue }
                if !place.latitude.isFinite
                    || !place.longitude.isFinite
                    || !(-90...90).contains(place.latitude)
                    || !(-180...180).contains(place.longitude) {
                    issues.append(.invalidCoordinate(activity.id))
                }
            }
        }

        var seenLegIDs: Set<TravelLegID> = []
        for preference in travelLegPreferences {
            let legID = preference.legID
            let trimmedNote = preference.note?.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDefault = preference.transportType == .automobile
                && preference.manualDurationMinutes == nil
                && trimmedNote == nil
            let isValidDuration = preference.manualDurationMinutes.map { (1...1_439).contains($0) } ?? true
            let isSameDay = dayIDByActivityID[legID.fromActivityID] != nil
                && dayIDByActivityID[legID.fromActivityID] == dayIDByActivityID[legID.toActivityID]
            let hasNormalizedNote = preference.note == nil || (trimmedNote?.isEmpty == false && preference.note == trimmedNote)
            if legID.fromActivityID == legID.toActivityID
                || !seenLegIDs.insert(legID).inserted
                || !isSameDay
                || !isValidDuration
                || !hasNormalizedNote
                || isDefault {
                issues.append(.invalidTravelLegPreference(legID))
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
