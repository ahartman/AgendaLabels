//
//  LabelsModel.swift
//  AgendaAssistent
//
//  Created by André Hartman on 18/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//

import EventKit
import UserNotifications

class LabelsModel {
    let labelNumbers = ["nrOfWeeks": 12, "nrPerWeek": 25, "nrPerDay": 6]

    var startCalendar: Date
    var endCalendar: Date
    var labelCalendars = [String: EKCalendar]()
    let eventStore = EKEventStore()
    let calendar = Calendar.current
    let dateFormatter = DateFormatter()

    init() {
        let calendar = Calendar.current
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 7 * labelNumbers["nrOfWeeks"]!)
        endCalendar = calendar.date(byAdding: dayComp, to: startCalendar)!
        dateFormatter.dateFormat = "d/M/yyyy"
    }

    public func doLabels() async {
        Task {
            do {
                let authorization = try await requestEventStoreAuthorization()
                guard authorization == .authorized else {
                    throw EventError.eventAuthorizationStatus(nil)
                }
            } catch {
                print("Probleem in getEvents")
            }
        }

        let calendars = eventStore.calendars(for: .event).filter { $0.title == "Marieke" || $0.title == "Marieke blokkeren" || $0.title == "Marieke speciallekes" }
        for calendar in calendars {
            labelCalendars[calendar.title] = calendar
        }

        let expiredSessions = getProposedEvents()
        let moveLabels = moveExpiredSessions(sessions: expiredSessions)
        for event in moveLabels {
            try? eventStore.save(event, span: .thisEvent)
        }

        let (sessions, newSessions, oldLabels, oldEvents) = getLabelEvents()
        let dayLabels = doDayCounts(sessions: sessions, newSessions: newSessions)
        let weekLabels = doWeekCounts(sessions: sessions, newSessions: newSessions)

        let oldStuff = oldLabels + oldEvents
        for event in oldStuff {
            try? eventStore.remove(event, span: .thisEvent)
        }
        for event in dayLabels! {
            try? eventStore.save(event, span: .thisEvent)
        }
        for event in weekLabels! {
            try? eventStore.save(event, span: .thisEvent)
        }
        try? eventStore.commit()

        showNotification(count: moveLabels.count)
    }

    func showNotification(count: Int) {
        let center = UNUserNotificationCenter.current()
        let tekst = count == 1 ? "voorstel" : "voorstellen"
        let content = UNMutableNotificationContent()
        content.title = "Agenda Labels"
        content.body = "\(count) \(tekst) verouderd."
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let request = UNNotificationRequest(identifier: "Identifier", content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Notificatie fout: \(error)")
            }
        }
    }

    private func moveExpiredSessions(sessions: [EKEvent]) -> [EKEvent] {
        var localSessions = [EKEvent]()

        for session in sessions {
            if let location = session.location {
                let year = calendar.dateComponents([.year], from: session.creationDate!).year!
                if let date = dateFormatter.date(from: location + "/\(year)") {
                    let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date()).day!
                    if numberOfDays > 14 {
                        // print("\(session.title),location: \(location), date: \(dateFormatter.string(from: date)),\(numberOfDays) \(session.calendar.title)")
                        session.calendar = labelCalendars["Marieke blokkeren"]
                        localSessions.append(session)
                    }
                }
            }
        }
        return localSessions
    }

    private func getLabelEvents() -> ([EKEvent], [EKEvent], [EKEvent], [EKEvent]) {
        let oldLabelsStartDate = calendar.date(byAdding: DateComponents(day: -7), to: startCalendar)!
        let labelsPredicate = eventStore.predicateForEvents(withStart: oldLabelsStartDate, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke blokkeren"]!])
        let labels = eventStore.events(matching: labelsPredicate).filter { $0.isAllDay == true }

        let sessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!])
        let sessions = eventStore.events(matching: sessionsPredicate).filter { $0.isAllDay == false }

        let newSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke speciallekes"]!])
        let newSessions = eventStore.events(matching: newSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

        let oldSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: Date(), calendars: [labelCalendars["Marieke speciallekes"]!, labelCalendars["Marieke blokkeren"]!])
        let oldSessions = eventStore.events(matching: oldSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

        return (sessions, newSessions, labels, oldSessions)
    }

    private func getProposedEvents() -> [EKEvent] {
        let proposedSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke speciallekes"]!])
        let proposedSessions = eventStore.events(matching: proposedSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }
        return (proposedSessions)
    }

    private func doDayCounts(sessions: [EKEvent], newSessions: [EKEvent]) -> [EKEvent]? {
        var datum = startCalendar
        var tempLabels = [EKEvent]()

        while datum <= endCalendar {
            let labelDayCount = sessions.filter { calendar.isDate(datum, inSameDayAs: $0.startDate) }.count
            let labelDayNewPatient = newSessions.filter {
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

    private func doWeekCounts(sessions: [EKEvent], newSessions: [EKEvent]) -> [EKEvent]? {
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
            let labelWeekNewCount = newSessions.filter {
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
