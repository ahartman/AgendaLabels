//
//  LabelsModel.swift
//  AgendaAssistent
//
//  Created by André Hartman on 18/12/2020.
//  Copyright © 2020 André Hartman. All rights reserved.
//

import Foundation

//
//  EventsRepository.swift
//  EventKit.Example
//
//  Created by Filip Němeček on 31/07/2020.
//  Copyright © 2020 Filip Němeček. All rights reserved.
//

import Foundation
import EventKit
import Combine

typealias Action = () -> ()

class LabelsModel {
    var selectedCalendarsSet: Set<EKCalendar>?
    var events: [EKEvent]?
    var startCalendar: Date
    var endCalendar: Date

    var labelCalendars = [String : EKCalendar]()
    let labelNumbers = ["nrOfWeeks": 8, "nrPerWeek" : 25, "nrPerDay": 7]
    var labelDayCounts = [Date : Int]()
    var labelWeekCounts = [Date : Int]()

    let eventStore = EKEventStore()
    let calendar = Calendar.current

    init() {
        let calendar = Calendar.current
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 7 * labelNumbers["nrOfWeeks"]!)
        endCalendar = Calendar.current.date(byAdding: dayComp, to: startCalendar)!
    }

    private func requestAccess(onGranted: @escaping Action, onDenied: @escaping Action) {
        eventStore.requestAccess(to: .event) { (granted, error) in
            if granted {
                onGranted()
            } else {
                onDenied()
            }
        }
    }

    public func doLabels() -> Void {
        var sessions: [EKEvent]?
        var oldLabels: [EKEvent]?
        var dayLabels: [EKEvent]?
        var weekLabels: [EKEvent]?

        let calendar = Calendar.current
        let monday = DateComponents(hour: 0, minute: 0, second: 0, weekday: 2)
        startCalendar = calendar.nextDate(after: Date(), matching: monday, matchingPolicy: .nextTime, direction: .backward)!
        let dayComp = DateComponents(day: 8 * 7)
        endCalendar = Calendar.current.date(byAdding: dayComp, to: startCalendar)!

        let calendars = eventStore.calendars(for: .event).filter({ $0.title == "Marieke" || $0.title == "Marieke blokkeren"})
        for calendar in calendars {
            labelCalendars[calendar.title] = calendar
        }

        let group = DispatchGroup()
        group.enter()
        getLabelEvents(completion: { (sessions1, labels1) in
            DispatchQueue.global(qos: .default).async {
                sessions = sessions1!
                oldLabels = labels1!
                group.leave()
            }
        })
        group.wait()
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

    private func getLabelEvents(completion: @escaping (([EKEvent]?, [EKEvent]?) -> Void)) {
        requestAccess(onGranted: {
            let predicate1 = self.eventStore.predicateForEvents(withStart: self.startCalendar, end: self.endCalendar, calendars: [self.labelCalendars["Marieke"]!, self.labelCalendars["Marieke blokkeren"]!])
            let labels1 = self.eventStore.events(matching: predicate1).filter({$0.isAllDay == true})
            let predicate2 = self.eventStore.predicateForEvents(withStart: self.startCalendar, end: self.endCalendar, calendars: [self.labelCalendars["Marieke"]!])
            let sessions1 = self.eventStore.events(matching: predicate2).filter {$0.isAllDay == false}
            completion(sessions1, labels1)
        }) {
            completion(nil, nil)
        }
    }

    private func doDayCounts(sessions: [EKEvent]) -> [EKEvent]? {
        var datum = startCalendar
        var tempLabels = [EKEvent]()
        while datum <= endCalendar {
            let labelDayCount = sessions.filter({calendar.isDate(datum, inSameDayAs: $0.startDate)}).count
            let labelDayNewPatient = sessions.filter({
                calendar.isDate(datum, inSameDayAs: $0.startDate) && $0.title.contains("#")
            }).count
            let event = EKEvent(eventStore: eventStore)
            event.startDate = datum
            event.endDate = datum
            event.isAllDay = true
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
        var weekDates = [Date]()
        while datum < endCalendar {
            let datumWeek = calendar.component(.weekOfYear, from: datum)
            let labelWeekCount = sessions.filter({
                let labelWeek = calendar.component(.weekOfYear, from: $0.startDate)
                return datumWeek == labelWeek
            }).count
            weekCounts.append(labelWeekCount)
            weekDates.append(datum)
            datum = calendar.date(byAdding: DateComponents(day: 7), to: datum)!
        }
        var weekLabels = weekCounts.map({String($0)})
        for (index, week) in weekCounts.enumerated() {
            let event = EKEvent(eventStore: eventStore)
            event.startDate = weekDates[index]
            event.endDate = calendar.date(byAdding: DateComponents(day: 7), to: event.startDate)!
            event.isAllDay = true
            event.title = "Week \(weekLabels.joined(separator: ", "))"
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
}


