import Foundation
import SwiftUI

enum GroupMissionDateState: Equatable, Sendable {
    case today
    case future
    case past
    case invalid
}

enum GroupMissionDate {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    static func todayString(now: Date = Date()) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0,
                      components.month ?? 0, components.day ?? 0)
    }

    static func state(for value: String, now: Date = Date()) -> GroupMissionDateState {
        guard let date = date(from: value) else { return .invalid }
        let today = calendar.startOfDay(for: now)
        let missionDay = calendar.startOfDay(for: date)
        if missionDay == today { return .today }
        return missionDay > today ? .future : .past
    }

    static func date(from value: String) -> Date? {
        guard let date = DateFormatter.japaneseDay.date(from: value) else { return nil }
        return date
    }
}

private extension DateFormatter {
    static var japaneseDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = GroupMissionDate.calendarForFormatter
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private extension GroupMissionDate {
    static var calendarForFormatter: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }
}

@MainActor
struct GroupPrototypeNotice: View {
    let dataMode: GroupUIDataMode

    var body: some View {
        Group {
            if dataMode == .fake {
                PrototypeNotice(message: "groups.notice.fake")
                    .accessibilityIdentifier("groups.notice.fake")
            }
        }
    }
}

extension GroupMissionStatus {
    var displayKey: LocalizedStringKey {
        switch self {
        case .awaitingPrompt: "groups.mission.awaiting"
        case .open: "groups.mission.open"
        case .closed: "groups.mission.closed"
        }
    }
}

extension GroupMemberStatus {
    var displayKey: LocalizedStringKey {
        switch self {
        case .active: "groups.status.active"
        case .left: "groups.status.left"
        case .removed: "groups.status.removed"
        }
    }
}

extension GroupRole {
    var displayKey: LocalizedStringKey {
        switch self {
        case .owner: "groups.owner"
        case .member: "groups.member"
        }
    }
}

extension GroupInvitationStatus {
    var displayKey: LocalizedStringKey {
        switch self {
        case .pending: "groups.invitation.pending"
        case .accepted: "groups.invitation.accepted"
        case .declined: "groups.invitation.declined"
        case .canceled: "groups.invitation.canceled"
        case .expired: "groups.invitation.expired"
        }
    }
}

enum GroupNotificationMessage {
    static func eventKey(_ eventType: String) -> LocalizedStringKey {
        switch eventType {
        case "GROUP_INVITED": "notifications.event.group-invitation"
        case "GROUP_INVITE_ACCEPTED": "notifications.event.group-invite-accepted"
        case "GROUP_MEMBER_REMOVED": "notifications.event.group-member"
        case "GROUP_OWNERSHIP_TRANSFERRED": "notifications.event.owner-transferred"
        case "GROUP_PROMPT_TURN": "notifications.event.prompt-turn"
        case "GROUP_MISSION_OPENED": "notifications.event.mission"
        case "GROUP_ANSWER_POSTED": "notifications.event.answer"
        default: "notifications.event.default"
        }
    }
}
