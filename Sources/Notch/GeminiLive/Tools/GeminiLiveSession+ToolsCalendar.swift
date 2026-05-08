@preconcurrency import Foundation
@preconcurrency import EventKit
import AppKit
import NotchTooling

extension GeminiLiveSession {
    // MARK: - Calendar Tool

    func executeCalendar(action: String, args: [String: Any]) -> [String: Any] {
        let store = Self.calendarStore

        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .notDetermined {
            let semaphore = DispatchSemaphore(value: 0)
            final class Box: @unchecked Sendable { var value = false }
            let granted = Box()
            store.requestFullAccessToEvents { result, _ in
                granted.value = result
                semaphore.signal()
            }
            semaphore.wait()
            guard granted.value else {
                return ["success": false, "error": "Calendar access was denied by the user."]
            }
        } else if status != .fullAccess {
            return ["success": false, "error": "Calendar access not granted. Enable in System Settings > Privacy & Security > Calendars."]
        }

        // Check reminders authorization if needed
        let isReminderAction = ["list_reminders", "create_reminder", "complete_reminder", "delete_reminder"].contains(action)
        if isReminderAction {
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            if reminderStatus == .notDetermined {
                let semaphore = DispatchSemaphore(value: 0)
                final class Box: @unchecked Sendable { var value = false }
                let granted = Box()
                store.requestFullAccessToReminders { result, _ in
                    granted.value = result
                    semaphore.signal()
                }
                semaphore.wait()
                guard granted.value else {
                    return ["success": false, "error": "Reminders access was denied by the user."]
                }
            } else if reminderStatus != .fullAccess {
                return ["success": false, "error": "Reminders access not granted. Enable in System Settings > Privacy & Security > Reminders."]
            }
        }

        switch action {
        case "list":
            return calendarList(store: store, args: args)
        case "create":
            return calendarCreate(store: store, args: args)
        case "delete":
            return calendarDelete(store: store, args: args)
        case "calendars":
            return calendarListCalendars(store: store)
        case "list_reminders":
            return reminderList(store: store, args: args)
        case "create_reminder":
            return reminderCreate(store: store, args: args)
        case "complete_reminder":
            return reminderComplete(store: store, args: args)
        case "delete_reminder":
            return reminderDelete(store: store, args: args)
        default:
            return ["success": false, "error": "Unknown action '\(action)'. Use: list, create, delete, calendars, list_reminders, create_reminder, complete_reminder, or delete_reminder."]
        }
    }

    private static let calendarDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let calendarDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, yyyy-MM-dd"
        return f
    }()

    // MARK: list

    private func calendarList(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        let cal = Calendar.current
        let now = Date()
        let daysBack = min(max((args["daysBack"] as? Int) ?? 0, 0), 30)
        let daysAhead = min(max((args["daysAhead"] as? Int) ?? 0, 0), 30)
        let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -daysBack, to: now)!)
        let endDate = cal.date(byAdding: .day, value: daysAhead + 1, to: cal.startOfDay(for: now))!

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        var events = store.events(matching: predicate)

        if let query, !query.isEmpty {
            events = events.filter { ($0.title ?? "").lowercased().contains(query) }
        }

        let df = Self.calendarDateFormatter
        let dayFmt = Self.calendarDayFormatter

        let eventEntries: [[String: Any]] = events.map { event in
            var entry: [String: Any] = [
                "id": event.eventIdentifier ?? "",
                "title": event.title ?? "(no title)",
                "start": df.string(from: event.startDate),
                "end": df.string(from: event.endDate),
                "allDay": event.isAllDay,
                "calendar": event.calendar.title,
            ]
            if let loc = event.location, !loc.isEmpty { entry["location"] = loc }
            if let notes = event.notes, !notes.isEmpty { entry["notes"] = String(notes.prefix(300)) }
            if event.hasRecurrenceRules { entry["recurring"] = true }
            return entry
        }

        let range: String
        if daysBack == 0 && daysAhead == 0 {
            range = "today (\(dayFmt.string(from: now)))"
        } else {
            range = "\(dayFmt.string(from: startDate)) → \(dayFmt.string(from: cal.date(byAdding: .day, value: -1, to: endDate)!))"
        }

        return [
            "success": true,
            "range": range,
            "eventCount": eventEntries.count,
            "events": eventEntries,
        ]
    }

    // MARK: create

    private func calendarCreate(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return ["success": false, "error": "Missing required field: title"]
        }

        let df = Self.calendarDateFormatter
        let isAllDay = (args["allDay"] as? Bool) ?? false

        let startDate: Date
        let endDate: Date

        if let startStr = args["startDate"] as? String, let parsed = df.date(from: startStr) {
            startDate = parsed
        } else if let startStr = args["startDate"] as? String {
            // Try date-only format for all-day events
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = dayOnly.date(from: startStr) {
                startDate = parsed
            } else {
                return ["success": false, "error": "Invalid startDate format. Use 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd'."]
            }
        } else {
            return ["success": false, "error": "Missing required field: startDate (format: 'yyyy-MM-dd HH:mm')"]
        }

        if let endStr = args["endDate"] as? String, let parsed = df.date(from: endStr) {
            endDate = parsed
        } else if let endStr = args["endDate"] as? String {
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")
            if let parsed = dayOnly.date(from: endStr) {
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: parsed)!
            } else {
                return ["success": false, "error": "Invalid endDate format. Use 'yyyy-MM-dd HH:mm' or 'yyyy-MM-dd'."]
            }
        } else if isAllDay {
            endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        } else {
            endDate = startDate.addingTimeInterval(3600) // default 1 hour
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = isAllDay

        if let location = args["location"] as? String, !location.isEmpty {
            event.location = location
        }
        if let notes = args["notes"] as? String, !notes.isEmpty {
            event.notes = notes
        }

        // Pick calendar
        if let calendarName = (args["calendarName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !calendarName.isEmpty {
            let match = store.calendars(for: .event).first {
                $0.title.lowercased() == calendarName.lowercased()
            }
            event.calendar = match ?? store.defaultCalendarForNewEvents
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        // Alert/notification
        let alertMinutes: Int?
        if let raw = args["alertMinutesBefore"] as? NSNumber {
            alertMinutes = raw.intValue
        } else if let raw = args["alertMinutesBefore"] as? Int {
            alertMinutes = raw
        } else {
            alertMinutes = nil
        }
        if let minutes = alertMinutes {
            let offset = -TimeInterval(max(minutes, 0) * 60)
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try store.save(event, span: .thisEvent)
            var eventInfo: [String: Any] = [
                "id": event.eventIdentifier ?? "",
                "title": event.title ?? "",
                "start": df.string(from: event.startDate),
                "end": df.string(from: event.endDate),
                "allDay": event.isAllDay,
                "calendar": event.calendar.title,
            ]
            if let minutes = alertMinutes {
                eventInfo["alert"] = minutes == 0 ? "at event time" : "\(minutes) min before"
            }
            return [
                "success": true,
                "message": "Event created successfully.",
                "event": eventInfo,
            ]
        } catch {
            return ["success": false, "error": "Failed to save event: \(error.localizedDescription)"]
        }
    }

    // MARK: delete

    private func calendarDelete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let eventId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !eventId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list' action first to get event IDs."]
        }

        guard let event = store.event(withIdentifier: eventId) else {
            return ["success": false, "error": "Event not found with ID: \(eventId)"]
        }

        let title = event.title ?? "(no title)"
        do {
            try store.remove(event, span: .thisEvent)
            return [
                "success": true,
                "message": "Deleted event: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to delete event: \(error.localizedDescription)"]
        }
    }

    // MARK: calendars (list available)

    private func calendarListCalendars(store: EKEventStore) -> [String: Any] {
        let calendars = store.calendars(for: .event)
        let entries: [[String: Any]] = calendars.map { cal in
            [
                "name": cal.title,
                "type": cal.type == .calDAV ? "CalDAV" :
                        cal.type == .exchange ? "Exchange" :
                        cal.type == .local ? "Local" :
                        cal.type == .subscription ? "Subscription" :
                        cal.type == .birthday ? "Birthday" : "Other",
                "source": cal.source?.title ?? "Unknown",
                "allowsModify": cal.allowsContentModifications,
            ]
        }

        return [
            "success": true,
            "calendarCount": entries.count,
            "calendars": entries,
        ]
    }

    // MARK: - Reminders

    private func reminderList(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        let query = (args["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let showCompleted = (args["isCompleted"] as? Bool) ?? false
        let listName = (args["reminderList"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        var targetCalendars: [EKCalendar]? = nil
        if let listName, !listName.isEmpty {
            let match = store.calendars(for: .reminder).filter {
                $0.title.lowercased() == listName.lowercased()
            }
            if !match.isEmpty { targetCalendars = match }
        }

        let predicate: NSPredicate
        if showCompleted {
            predicate = store.predicateForCompletedReminders(
                withCompletionDateStarting: Calendar.current.date(byAdding: .month, value: -3, to: Date()),
                ending: Date(),
                calendars: targetCalendars
            )
        } else {
            predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: targetCalendars
            )
        }

        let semaphore = DispatchSemaphore(value: 0)
        var fetchedReminders: [EKReminder] = []
        store.fetchReminders(matching: predicate) { reminders in
            fetchedReminders = reminders ?? []
            semaphore.signal()
        }
        semaphore.wait()

        if let query, !query.isEmpty {
            fetchedReminders = fetchedReminders.filter {
                ($0.title ?? "").lowercased().contains(query)
            }
        }

        let df = Self.calendarDateFormatter
        let entries: [[String: Any]] = fetchedReminders.prefix(50).map { reminder in
            var entry: [String: Any] = [
                "id": reminder.calendarItemIdentifier,
                "title": reminder.title ?? "(no title)",
                "completed": reminder.isCompleted,
                "list": reminder.calendar.title,
            ]
            if let dueDate = reminder.dueDateComponents,
               let date = Calendar.current.date(from: dueDate) {
                entry["dueDate"] = df.string(from: date)
            }
            if let notes = reminder.notes, !notes.isEmpty {
                entry["notes"] = String(notes.prefix(200))
            }
            if let completionDate = reminder.completionDate {
                entry["completedDate"] = df.string(from: completionDate)
            }
            if reminder.priority > 0 {
                entry["priority"] = reminder.priority
            }
            return entry
        }

        return [
            "success": true,
            "filter": showCompleted ? "completed" : "pending",
            "reminderCount": entries.count,
            "reminders": entries,
        ]
    }

    private func reminderCreate(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let title = (args["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return ["success": false, "error": "Missing required field: title"]
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title

        // Pick reminder list — defaultCalendarForNewReminders() can return nil on some setups.
        let allReminderCalendars = store.calendars(for: .reminder)
        let resolvedCalendar: EKCalendar?

        if let listName = (args["reminderList"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !listName.isEmpty {
            let match = allReminderCalendars.first {
                $0.title.lowercased() == listName.lowercased()
            }
            resolvedCalendar = match
                ?? store.defaultCalendarForNewReminders()
                ?? allReminderCalendars.first(where: { $0.allowsContentModifications })
        } else {
            resolvedCalendar = store.defaultCalendarForNewReminders()
                ?? allReminderCalendars.first(where: { $0.allowsContentModifications })
        }

        guard let targetCalendar = resolvedCalendar else {
            let available = allReminderCalendars.map { $0.title }.joined(separator: ", ")
            return ["success": false, "error": "No writable reminder list found. Available lists: \(available.isEmpty ? "none" : available). Open Reminders.app and create a list first."]
        }
        reminder.calendar = targetCalendar

        // Due date
        if let startStr = args["startDate"] as? String {
            let df = Self.calendarDateFormatter
            let dayOnly = DateFormatter()
            dayOnly.dateFormat = "yyyy-MM-dd"
            dayOnly.locale = Locale(identifier: "en_US_POSIX")

            if let parsed = df.date(from: startStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: parsed
                )
            } else if let parsed = dayOnly.date(from: startStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day], from: parsed
                )
            }
        }

        if let notes = args["notes"] as? String, !notes.isEmpty {
            reminder.notes = notes
        }

        // Alert — for reminders, default to alerting at the due time (offset 0)
        let alertMinutes: Int
        if let raw = args["alertMinutesBefore"] as? NSNumber {
            alertMinutes = raw.intValue
        } else if let raw = args["alertMinutesBefore"] as? Int {
            alertMinutes = raw
        } else {
            alertMinutes = 0  // default: alert exactly at due time
        }
        if reminder.dueDateComponents != nil {
            let offset = -TimeInterval(max(alertMinutes, 0) * 60)
            reminder.addAlarm(EKAlarm(relativeOffset: offset))
        }

        do {
            try store.save(reminder, commit: true)
            var info: [String: Any] = [
                "id": reminder.calendarItemIdentifier,
                "title": reminder.title ?? "",
                "list": reminder.calendar.title,
            ]
            if let dc = reminder.dueDateComponents,
               let date = Calendar.current.date(from: dc) {
                info["dueDate"] = Self.calendarDateFormatter.string(from: date)
            }
            info["alert"] = alertMinutes == 0 ? "at due time" : "\(alertMinutes) min before"
            return [
                "success": true,
                "message": "Reminder created successfully.",
                "reminder": info,
            ]
        } catch {
            return ["success": false, "error": "Failed to save reminder: \(error.localizedDescription)"]
        }
    }

    private func reminderComplete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let reminderId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reminderId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list_reminders' first."]
        }

        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return ["success": false, "error": "Reminder not found with ID: \(reminderId)"]
        }

        let title = item.title ?? "(no title)"
        item.isCompleted = true
        item.completionDate = Date()

        do {
            try store.save(item, commit: true)
            return [
                "success": true,
                "message": "Completed reminder: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to complete reminder: \(error.localizedDescription)"]
        }
    }

    private func reminderDelete(store: EKEventStore, args: [String: Any]) -> [String: Any] {
        guard let reminderId = (args["eventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reminderId.isEmpty else {
            return ["success": false, "error": "Missing required field: eventId. Use 'list_reminders' first."]
        }

        guard let item = store.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return ["success": false, "error": "Reminder not found with ID: \(reminderId)"]
        }

        let title = item.title ?? "(no title)"
        do {
            try store.remove(item, commit: true)
            return [
                "success": true,
                "message": "Deleted reminder: \(title)",
            ]
        } catch {
            return ["success": false, "error": "Failed to delete reminder: \(error.localizedDescription)"]
        }
    }
}
