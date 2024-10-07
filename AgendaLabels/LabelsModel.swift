//
//  LabelsModel.swift
//  AgendaAssistent
//
//  Created by André Hartman on 18/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//
import EventKit

class LabelsModel {
    let labelNumbers = [
        "nrOfWeeks": 26,
        "nrPerWeek": 25,
        "nrPerDay": 6,
        "minimumPerWeek": 5,
        "expiryDays": 7
    ]

    let startCalendar: Date
    var endCalendar: Date
    var endWeeklyCalendar: Date

    var labelCalendars = [String: EKCalendar]()
    let eventStore = EKEventStore()
    let calendar = Calendar.current
    let df = DateFormatter()
    let defaults = UserDefaults.standard
    let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)

    init() {
        startCalendar = calendar.nextDate(
            after: Date(), matching: monday,
            matchingPolicy: .nextTime,
            direction: .backward
        )!
        let dayComp = DateComponents(day: 7 * labelNumbers["nrOfWeeks"]!)
        endCalendar = calendar.date(byAdding: dayComp, to: startCalendar)!
        endWeeklyCalendar = endCalendar

        df.dateFormat = "d/M/yyyy"
        df.locale = Locale(identifier: "nl_BE")

        if defaults.object(forKey: "labelsToday") == nil {
            defaults.set(Date(), forKey: "labelsToday")
        }
    }

    func doLabels() async {
        let permit = Task {
            let eventStore = EKEventStore()
            guard try await eventStore.requestAccess(to: .event) else {
                print("calendar access probleem")
                return false
            }
            return true
        }
        do {
            _ = try await permit.value
        } catch {
            print("problem")
        }
        doLabels1()
    }

    public func doLabels1() {
        let calendars = eventStore.calendars(for: .event)
            .filter { $0.title.contains("Marieke") }
        for calendar in calendars {
            labelCalendars[calendar.title] = calendar
        }
        if labelCalendars.count == 0 { print("Geen agenda's") }

        // handle expired first
        if !calendar.isDateInToday(defaults.object(forKey: "labelsToday") as! Date) {
            let findSessionsPredicate = eventStore.predicateForEvents(
                withStart: startCalendar,
                end: endCalendar,
                calendars: [labelCalendars["Marieke speciallekes"]!]
            )
            let findSessions = eventStore.events(matching: findSessionsPredicate)
                .filter { !$0.isAllDay }
                .filter {
                    let temp = $0.location ?? ""
                    return !["afgezegd", "niet gekomen","hier","daar"].contains(temp.lowercased())
                }
            let toMoveSessions = moveExpiredSessions(sessions: findSessions)
            for event in toMoveSessions {
                try? eventStore.save(event, span: .thisEvent)
            }
            defaults.set(Date(), forKey: "labelsToday")
        }

        let (sessions, newSessions, proposedSessions, oldLabels, oldSessions) = getLabelEvents()
        let weekLabels = doWeekLabels(sessions: sessions, newSessions: newSessions, proposedSessions: proposedSessions)
        let newLabels = doWeekProposedLabels(newSessions: newSessions, proposedSessions: proposedSessions)
        let dayLabels = doDayLabels(sessions: sessions, newSessions: newSessions, proposedSessions: proposedSessions)
        let moveNewSessions = moveNewSessions(sessions: newSessions)

        for event in oldLabels + oldSessions {
            try? eventStore.remove(event, span: .thisEvent)
        }
        for event in weekLabels + newLabels + dayLabels + moveNewSessions {
            try? eventStore.save(event, span: .thisEvent)
        }
        try? eventStore.commit()
    }

    func moveExpiredSessions(sessions: [EKEvent]) -> [EKEvent] {
        var localSessions = [EKEvent]()
        for session in sessions {
            let item = eventStore.event(withIdentifier: session.eventIdentifier)
            let gemaakt = calendar.startOfDay(for: (item?.creationDate)!)

            let numberOfDays = Calendar.current.dateComponents([.day], from: gemaakt, to: Date()).day!
            if numberOfDays > labelNumbers["expiryDays"]! {
                session.calendar = labelCalendars["Marieke blokkeren"]
                session.location = "niet tijdig gereageerd"
                localSessions.append(session)
            }
        }
        return localSessions
    }

    func moveNewSessions(sessions: [EKEvent]) -> [EKEvent] {
        let date = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let newSessions = sessions.map {
            $0.calendar = $0.startDate < date ? labelCalendars["Marieke"] : labelCalendars["Marieke nieuwe"]
            return $0
        }
        return newSessions
    }

    func getLabelEvents() -> ([EKEvent], [EKEvent], [EKEvent], [EKEvent], [EKEvent]) {
        let oldLabelsStartDate = calendar.date(byAdding: DateComponents(day: -7), to: startCalendar)!
        let oldLabelsPredicate = eventStore.predicateForEvents(withStart: oldLabelsStartDate, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke blokkeren"]!, labelCalendars["Marieke speciallekes"]!, labelCalendars["Marieke nieuwe"]!])
        let oldLabels = eventStore.events(matching: oldLabelsPredicate).filter { $0.isAllDay == true }

        let sessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke nieuwe"]!])
        let sessions = eventStore.events(matching: sessionsPredicate).filter { $0.isAllDay == false }

        let newSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke nieuwe"]!])
        let newSessions = eventStore.events(matching: newSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

        let proposedSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke speciallekes"]!])
        let proposedSessions = eventStore.events(matching: proposedSessionsPredicate).filter {
            let temp = $0.location ?? ""
            return
                !["afgezegd"].contains(temp.lowercased()) &&
                $0.isAllDay == false &&
                $0.title.contains("#")
        }
 
        let oldSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: Date(), calendars: [labelCalendars["Marieke speciallekes"]!, labelCalendars["Marieke blokkeren"]!])
        let oldSessions = eventStore.events(matching: oldSessionsPredicate)
            .filter {
                let temp = $0.location ?? ""
                return
                    !["afgezegd", "niet gekomen"].contains(temp.lowercased()) &&
                    $0.isAllDay == false &&
                    $0.title.contains("#")
            }
        return (sessions, newSessions, proposedSessions, oldLabels, oldSessions)
    }

    func doWeekLabels(sessions: [EKEvent], newSessions: [EKEvent], proposedSessions: [EKEvent]) -> [EKEvent] {
        var datum = startCalendar
        var localLabels = [EKEvent]()

        var weekCounts = [Int]()
        var weekNewCounts = [Int]()
        var weekProposalsCounts = [Int]()
        var weekDates = [Date]()

        while datum < endCalendar {
            let datumWeek = calendar.component(.weekOfYear, from: datum)
            weekCounts.append(sessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek
            }.count)
            weekNewCounts.append(newSessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek && $0.title.contains("#")
            }.count)
            weekProposalsCounts.append(proposedSessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek && $0.title.contains("#")
            }.count)
            weekDates.append(datum)
            datum = calendar.date(byAdding: DateComponents(day: 7), to: datum)!
        }

        let lastIndex = weekCounts.lastIndex(where: { $0 > labelNumbers["minimumPerWeek"]! })
        weekCounts = Array(weekCounts[...lastIndex!])
        endCalendar = calendar.date(byAdding: DateComponents(day: 7), to: weekDates[lastIndex!])!
        endWeeklyCalendar = endCalendar

        var weekLabels = weekCounts.map { String($0) }
        for (index, week) in weekCounts.enumerated() {
            let event = EKEvent(eventStore: eventStore)
            event.isAllDay = true
            event.startDate = weekDates[index]
            event.endDate = calendar.date(byAdding: DateComponents(day: 6), to: event.startDate)!
            event.title = "Week \(weekLabels.joined(separator: ", "))"
            if week > labelNumbers["nrPerWeek"]! {
                event.calendar = labelCalendars["Marieke"]
            } else {
                event.calendar = labelCalendars["Marieke blokkeren"]
            }
            localLabels.append(event)
            weekLabels = Array(weekLabels.dropFirst())
        }
        return localLabels
    }

    func doDayLabels(sessions: [EKEvent], newSessions: [EKEvent], proposedSessions: [EKEvent]) -> [EKEvent] {
        var datum = startCalendar
        var localLabels = [EKEvent]()

        while datum <= endCalendar {
            let labelDayCount = sessions.filter { calendar.isDate(datum, inSameDayAs: $0.startDate) }.count
            let labelDayNewCount = newSessions.filter {
                calendar.isDate(datum, inSameDayAs: $0.startDate) && $0.title.contains("#")
            }.count
            let labelDayProposedcount = proposedSessions.filter {
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
            if labelDayNewCount > 0 {
                event.title = "\(event.title!) N#"
                if labelDayCount == 0 { event.calendar = labelCalendars["Marieke blokkeren"] }
            } else if labelDayProposedcount > 0 {
                event.title = "\(event.title!) V#"
                if labelDayCount == 0 { event.calendar = labelCalendars["Marieke blokkeren"] }
            }
            if datum < endWeeklyCalendar || event.title.contains("#"), event.title != "" {
                localLabels.append(event)
            }
            datum = calendar.date(byAdding: DateComponents(day: 1), to: datum)!
        }

        // check sync event
        let event = EKEvent(eventStore: eventStore)
        df.dateFormat = "ccc, HH:mm"
        let tijd = Date.now
        event.title = df.string(from: tijd).capitalized
        event.calendar = labelCalendars["Marieke blokkeren"]
        event.isAllDay = true
        event.startDate = tijd
        event.endDate = tijd
        localLabels.append(event)

        return localLabels
    }

    func doWeekProposedLabels(newSessions: [EKEvent], proposedSessions: [EKEvent]) -> [EKEvent] {
        var datum = startCalendar
        var localLabels = [EKEvent]()
        var weekNewCounts = [Int]()
        var weekProposalsCounts = [Int]()
        var weekDates = [Date]()

        endCalendar = max(
            newSessions.count > 0 ? newSessions.last!.startDate : Date(),
            proposedSessions.count > 0 ? proposedSessions.last!.startDate : Date()
        )
        while datum < endCalendar {
            let datumWeek = calendar.component(.weekOfYear, from: datum)
            weekNewCounts.append(newSessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek && $0.title.contains("#")
            }.count)
            weekProposalsCounts.append(proposedSessions.filter {
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek && $0.title.contains("#")
            }.count)
            weekDates.append(datum)
            datum = calendar.date(byAdding: DateComponents(day: 7), to: datum)!
        }

        let weekNewLabels = weekNewCounts.map { String($0) }
        let weekProposalsLabels = weekProposalsCounts.map { String($0) }

        for (index, _) in weekNewLabels.enumerated() {
            let event = EKEvent(eventStore: eventStore)
            event.isAllDay = true
            event.startDate = weekDates[index]
            event.endDate = calendar.date(byAdding: DateComponents(day: 6), to: event.startDate)!
            event.title = "Nieuwe: \(weekNewLabels[index]), voorstellen: \(weekProposalsLabels[index])"
            event.calendar = labelCalendars["Marieke nieuwe"]
            localLabels.append(event)
        }
        return localLabels
    }

    func requestEventStoreAuthorization() async throws -> EKAuthorizationStatus {
        if try await eventStore.requestAccess(to: .event) {
            return EKEventStore.authorizationStatus(for: .event)
        } else {
            throw EventError.unableToAccessCalendar
        }
    }

    enum EventError: Error, LocalizedError {
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
