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
    let labelNumbers = ["nrOfWeeks": 26, "nrPerWeek": 25, "nrPerDay": 6, "minimumPerWeek": 5]

    let startCalendar: Date
    var endCalendar: Date
    var endWeeklyCalendar: Date

    var labelCalendars = [String: EKCalendar]()
    let eventStore = EKEventStore()
    let calendar = Calendar.current
    let df = DateFormatter()
    let defaults = UserDefaults.standard

    init() {
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 7 * labelNumbers["nrOfWeeks"]!)
        endCalendar = calendar.date(byAdding: dayComp, to: startCalendar)!
        endWeeklyCalendar = endCalendar

        let calendars = eventStore.calendars(for: .event).filter { $0.title.contains("Marieke") }
        for calendar in calendars { labelCalendars[calendar.title] = calendar }

        df.dateFormat = "d/M/yyyy"

        if defaults.object(forKey: "today") == nil {
            defaults.set(Date(), forKey: "today")
        }
    }

    public func doLabels() async {
        var verwijderd = 0
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

        // handle expired first
        if !calendar.isDateInToday(defaults.object(forKey: "today") as! Date) {
            var proposedSessions = [EKEvent]()
            func getProposedEvents() {
                let proposedSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke speciallekes"]!])
                proposedSessions = eventStore.events(matching: proposedSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }
            }

            getProposedEvents()
            let toMoveSessions = moveExpiredSessions(sessions: proposedSessions)
            verwijderd = toMoveSessions.count
            for event in toMoveSessions {
                print(event)
                try? eventStore.save(event, span: .thisEvent)
            }
            try? eventStore.commit()
        }

        let (sessions, newSessions, proposedSessions, oldLabels, oldEvents) = getLabelEvents()
        let weekLabels = doWeekLabels(sessions: sessions, newSessions: newSessions, proposedSessions: proposedSessions)
        let newLabels = doWeekProposedLabels(newSessions: newSessions, proposedSessions: proposedSessions)
        let dayLabels = doDayLabels(sessions: sessions, newSessions: newSessions, proposedSessions: proposedSessions)

        for event in oldLabels + oldEvents {
            try? eventStore.remove(event, span: .thisEvent)
        }
        for event in weekLabels + newLabels + dayLabels {
            try? eventStore.save(event, span: .thisEvent)
        }
        try? eventStore.commit()

        if !calendar.isDateInToday(defaults.object(forKey: "today") as! Date) {
            showNotification(nieuwe: newSessions.count, voorstellen: proposedSessions.count/2, verwijderd: verwijderd/2)
            // sendMail(nieuwe: newSessions.count, voorstellen: proposedSessions.count/2, verwijderd: verwijderd/2)
            defaults.set(Date(), forKey: "today")
        }
    }

    func moveExpiredSessions(sessions: [EKEvent]) -> [EKEvent] {
        var localSessions = [EKEvent]()
        for session in sessions {
            if let location = session.location {
                var validDate: Date?
                let year = calendar.dateComponents([.year], from: session.creationDate!).year!
                let potentialDate = location.components(separatedBy: ",")[0]
                if let date = df.date(from: potentialDate) {
                    validDate = date
                } else if let date = df.date(from: location + "/\(year)") {
                    validDate = date
                }
                if let date = validDate {
                    let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: Date()).day!
                    if numberOfDays > 7 {
                        session.calendar = labelCalendars["Marieke blokkeren"]
                        localSessions.append(session)
                    }
                }
            }
        }
        return localSessions
    }

    func showNotification(nieuwe: Int, voorstellen: Int, verwijderd: Int) {
        let center = UNUserNotificationCenter.current()
        let tekstVoorstellen = voorstellen == 1 ? "voorstel" : "voorstellen"
        let tekstVerwijderd = verwijderd == 1 ? "voorstel" : "voorstellen"

        let content = UNMutableNotificationContent()
        content.title = "Agenda Labels"
        content.body = "\(nieuwe) nieuwe, \(voorstellen) \(tekstVoorstellen).\n\(verwijderd) \(tekstVerwijderd) verouderd."
        print(content.body)
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5.0, repeats: false)
        let request = UNNotificationRequest(identifier: "Identifier", content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Notificatie fout: \(error)")
            }
        }
    }

    func sendMail(nieuwe: Int, voorstellen: Int, verwijderd: Int) {
        let component = calendar.component(.weekday, from: Date())
        if component == 1 || component == 7 { return }

        let tekstConsultaties = nieuwe == 1 ? "nieuwe consultatie" : "nieuwe consultaties"
        let tekstVoorstellen = voorstellen == 1 ? "voorgestelde consultatie" : "voorgestelde consultaties"
        let tekstVerwijderd = verwijderd == 1 ? "verouderd voorstel" : "verouderde voorstellen"
        let tekst = "\(nieuwe) \(tekstConsultaties).\n\(voorstellen) \(tekstVoorstellen).\n\(verwijderd) \(tekstVerwijderd) verwijderd."

        let myAppleScript = """
            tell application "Mail"
            set theTos to {"a.hartman@telenet.be"}
            set theMessage to make new outgoing message with properties {sender:"a.hartman@telenet.be", subject:"Marieke Agenda", content:"\(tekst)", visible:false}
                tell theMessage
                    repeat with theTo in theTos
                        make new recipient at end of to recipients with properties {address:theTo}
                    end repeat
                end tell
                send theMessage
            end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: myAppleScript) {
            if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
                print(outputString)
            } else if error != nil {
                print("error: ", error!)
            }
        }
    }

    func getLabelEvents() -> ([EKEvent], [EKEvent], [EKEvent], [EKEvent], [EKEvent]) {
        let oldLabelsStartDate = calendar.date(byAdding: DateComponents(day: -7), to: startCalendar)!
        let oldLabelsPredicate = eventStore.predicateForEvents(withStart: oldLabelsStartDate, end: endCalendar, calendars: [labelCalendars["Marieke"]!, labelCalendars["Marieke blokkeren"]!, labelCalendars["Marieke speciallekes"]!])
        let oldLabels = eventStore.events(matching: oldLabelsPredicate).filter { $0.isAllDay == true }

        let sessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!])
        let sessions = eventStore.events(matching: sessionsPredicate).filter { $0.isAllDay == false }

        let newSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke"]!])
        let newSessions = eventStore.events(matching: newSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

        let proposedSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: endCalendar, calendars: [labelCalendars["Marieke speciallekes"]!])
        let proposedSessions = eventStore.events(matching: proposedSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

        let oldSessionsPredicate = eventStore.predicateForEvents(withStart: startCalendar, end: Date(), calendars: [labelCalendars["Marieke speciallekes"]!, labelCalendars["Marieke blokkeren"]!])
        let oldSessions = eventStore.events(matching: oldSessionsPredicate).filter { $0.isAllDay == false && $0.title.contains("#") }

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
            event.endDate = calendar.date(byAdding: DateComponents(day: 7), to: event.startDate)!
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
            if datum < endWeeklyCalendar || event.title.contains("#") {
                localLabels.append(event)
            }
            datum = calendar.date(byAdding: DateComponents(day: 1), to: datum)!
        }
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
            event.endDate = calendar.date(byAdding: DateComponents(day: 7), to: event.startDate)!
            event.title = "Nieuwe: \(weekNewLabels[index]), voorstellen: \(weekProposalsLabels[index])"
            event.calendar = labelCalendars["Marieke speciallekes"]
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
