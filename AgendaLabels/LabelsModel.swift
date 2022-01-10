//
//  LabelsModel.swift
//  AgendaAssistent
//
//  Created by André Hartman on 18/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//

import Combine
import EventKit
import Foundation

typealias Action = () -> Void

class LabelsModelAsync {
    var selectedCalendarsSet: Set<EKCalendar>?
    var events: [EKEvent]?
    var startCalendar: Date
    var endCalendar: Date

    var labelCalendars = [String: EKCalendar]()
    let labelNumbers = ["nrOfWeeks": 8, "nrPerWeek": 30, "nrPerDay": 7]
    var labelDayCounts = [Date: Int]()
    var labelWeekCounts = [Date: Int]()

    let eventStore = EKEventStore()
    let calendar = Calendar.current

    init() {
        let calendar = Calendar.current
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 7 * labelNumbers["nrOfWeeks"]!)
        endCalendar = calendar.date(byAdding: dayComp, to: startCalendar)!
    }

    public func doLabels() async {
        var sessions: [EKEvent]?
        var oldLabels: [EKEvent]?
        var dayLabels: [EKEvent]?
        var weekLabels: [EKEvent]?

        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 10 * 7)
        endCalendar = calendar.date(byAdding: dayComp, to: startCalendar)!

        let calendars = eventStore.calendars(for: .event).filter { $0.title == "Marieke" || $0.title == "Marieke blokkeren" }
        for calendar in calendars {
            labelCalendars[calendar.title] = calendar
        }

        (sessions, oldLabels) = getLabelEvents()
        dayLabels = doDayCounts(sessions: sessions!)
        weekLabels = doWeekCounts(sessions: sessions!)

        for event in oldLabels! {
            try? eventStore.remove(event, span: .thisEvent)
        }
        for event in dayLabels! {
            try? eventStore.save(event, span: .thisEvent)
        }
        for event in weekLabels! {
            try? eventStore.save(event, span: .thisEvent)
        }
        try? eventStore.commit()
    }

    private func getLabelEvents() -> ([EKEvent]?, [EKEvent]?) {
        Task {
            do {
                let authorization = try await requestEventStoreAuthorization()
                guard authorization == .authorized else {
                    throw EventError.eventAuthorizationStatus(nil)
                }
            } catch {
                print("problem in loadAndUpdateEvents")
            }
        }

        let oldLabelsStartDate = calendar.date(byAdding: DateComponents(day: -7), to: startCalendar)!
        let labelsPredicate = eventStore.predicateForEvents(withStart: oldLabelsStartDate, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke blokkeren"]!])
        let labels = eventStore.events(matching: labelsPredicate).filter { $0.isAllDay == true }

        let sessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!])
        let sessions = eventStore.events(matching: sessionsPredicate).filter { $0.isAllDay == false }
        return (sessions, labels)
    }

    private func doDayCounts(sessions: [EKEvent]) -> [EKEvent]? {
        var datum = startCalendar
        var tempLabels = [EKEvent]()

        while datum <= endCalendar {
            let labelDayCount = sessions.filter { calendar.isDate(datum, inSameDayAs: $0.startDate) }.count
            let labelDayNewPatient = sessions.filter {
                calendar.isDate(datum, inSameDayAs: $0.startDate) && $0.title.contains("#")
            }.count

            let event = EKEvent(eventStore: eventStore)
            event.isAllDay = true
            event.startDate = datum
            event.endDate = datum

            if labelDayCount > labelNumbers["nrPerDay"]! {
                event.title = "Vol \(labelDayCount)"
                event.calendar = labelCalendars["Marieke"]
            } else if labelDayCount > 0 {
                event.title = "Dag \(labelDayCount)"
                event.calendar = labelCalendars["Marieke blokkeren"]
            }
            if labelDayNewPatient > 0 {
                event.title = "\(event.title!) #"
            }

            tempLabels.append(event)
            datum = calendar.date(byAdding: DateComponents(day: 1), to: datum)!
        }
        return tempLabels
    }

    private func doWeekCounts(sessions: [EKEvent]) -> [EKEvent]? {
        var datum = startCalendar
        var tempLabels = [EKEvent]()
        var weekCounts = [Int]()
        var weekNewCounts = [Int]()
        var weekDates = [Date]()
        while datum < endCalendar {
            let datumWeek = calendar.component(.weekOfYear, from: datum)
            let labelWeekCount = sessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek
            }.count
            let labelWeekNewCount = sessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek && $0.title.contains("#")
            }.count
            weekCounts.append(labelWeekCount)
            weekNewCounts.append(labelWeekNewCount)
            weekDates.append(datum)
            datum = calendar.date(byAdding: DateComponents(day: 7), to: datum)!
        }

        var weekLabels = weekCounts.map { String($0) }
        let weekNewLabels = weekNewCounts.map { String($0) }

        for (index, week) in weekCounts.enumerated() {
            let event = EKEvent(eventStore: eventStore)
            event.isAllDay = true
            event.startDate = weekDates[index]
            event.endDate = calendar.date(byAdding: DateComponents(day: 7), to: event.startDate)!
            event.title = "Week \(weekLabels.joined(separator: ", "))" + " (\(weekNewLabels[index])#)"
            if week > labelNumbers["nrPerWeek"]! {
                event.calendar = labelCalendars["Marieke"]
            } else {
                event.calendar = labelCalendars["Marieke blokkeren"]
            }
            weekLabels = Array(weekLabels.dropFirst())
            tempLabels.append(event)
        }
        return tempLabels
    }

    private func requestEventStoreAuthorization() async throws -> EKAuthorizationStatus {
        if try await eventStore.requestAccess(to: .event) {
            return EKEventStore.authorizationStatus(for: .event)
        } else {
            throw EventError.unableToAccessCalendar
        }
    }

    private enum EventError: Error, LocalizedError {
        case unableToAccessCalendar
        case eventAuthorizationStatus(EKAuthorizationStatus? = nil)

        var localizedDescription: String {
            switch self {
            case .unableToAccessCalendar: return "Unable to access celendar"
            case let .eventAuthorizationStatus(status):
                if let status = status {
                    return "Failed to authorize event permisssion, status: \(status)"
                } else {
                    return "Failed to authorize event permission"
                }
            }
        }
    }
}
