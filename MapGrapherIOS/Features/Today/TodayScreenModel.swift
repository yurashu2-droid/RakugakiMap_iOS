import Combine
import Foundation
import MapGrapherCore

/// 今週のどの日にのこしたかを読む口。投稿の日付を返すサーバー側の読み口がまだ無いので、今は試作の値だけを返す
protocol TodayFootprintReading: Sendable {
    var isPrototype: Bool { get }
    func postedDays(weekStartingAt monday: Date, calendar: Calendar) async throws -> Set<Date>
}

/// 試作のあしあと。今週の木曜日だけのこしたことにする（今日より先の日は返さない）
struct FakeTodayFootprintReader: TodayFootprintReading {
    var isPrototype: Bool { true }

    func postedDays(weekStartingAt monday: Date, calendar: Calendar) async throws -> Set<Date> {
        guard let thursday = calendar.date(byAdding: .day, value: 3, to: monday),
              thursday <= calendar.startOfDay(for: .now) else { return [] }
        return [thursday]
    }
}

/// 今週のあしあとの1日分
struct TodayWeekDay: Identifiable, Equatable {
    enum Status: Equatable {
        case posted
        case today
        case past
        case future
    }

    let date: Date
    let dayOfMonth: Int
    let index: Int
    let status: Status
    let isToday: Bool

    var id: Date { date }
}

enum TodayWeek {
    /// 月曜から日曜までの7日を並べる。のこした日は`posted`、まだの今日は`today`
    static func days(today: Date, posted: Set<Date>, calendar: Calendar) -> [TodayWeekDay] {
        let start = monday(of: today, calendar: calendar)
        let todayStart = calendar.startOfDay(for: today)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let isToday = date == todayStart
            let status: TodayWeekDay.Status
            if posted.contains(date) {
                status = .posted
            } else if isToday {
                status = .today
            } else if date > todayStart {
                status = .future
            } else {
                status = .past
            }
            return TodayWeekDay(date: date, dayOfMonth: calendar.component(.day, from: date),
                                index: offset, status: status, isToday: isToday)
        }
    }

    static func monday(of date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        // weekday：日曜=1、月曜=2 …
        let weekday = calendar.component(.weekday, from: start)
        let back = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -back, to: start) ?? start
    }

    /// 今日が終わるまでの時間（切り捨て）。1時間を切ったらnil（「まもなく締切」と出す）
    static func hoursLeft(now: Date, calendar: Calendar) -> Int? {
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let minutes = Int(end.timeIntervalSince(now) / 60)
        return minutes < 60 ? nil : minutes / 60
    }
}

@MainActor
final class TodayScreenModel: ObservableObject {
    @Published private(set) var displayName: String?
    @Published private(set) var group: GroupSummary?
    @Published private(set) var week: [TodayWeekDay] = []

    let groupsDataMode: GroupUIDataMode
    let footprintsArePrototype: Bool

    private let groupsService: any GroupsServing
    private let context: SessionContext?
    private let socialService: any SocialProfileUIService
    private let footprints: any TodayFootprintReading
    private let calendar: Calendar

    init(groupsService: any GroupsServing, context: SessionContext?, groupsDataMode: GroupUIDataMode,
         socialService: any SocialProfileUIService, footprints: any TodayFootprintReading,
         calendar: Calendar = .current) {
        self.groupsService = groupsService
        self.context = context
        self.groupsDataMode = groupsDataMode
        self.socialService = socialService
        self.footprints = footprints
        self.footprintsArePrototype = footprints.isPrototype
        self.calendar = calendar
        week = TodayWeek.days(today: .now, posted: [], calendar: calendar)
    }

    var postedCount: Int {
        week.filter { $0.status == .posted }.count
    }

    func load() async {
        let now = Date.now
        let monday = TodayWeek.monday(of: now, calendar: calendar)
        let posted = (try? await footprints.postedDays(weekStartingAt: monday, calendar: calendar)) ?? []
        week = TodayWeek.days(today: now, posted: posted, calendar: calendar)
        displayName = try? await socialService.currentProfile()?.displayName
        group = await pickGroup()
    }

    // いちばん先に答えたいグループ（お題があり、まだ答えていないもの）を見せる
    private func pickGroup() async -> GroupSummary? {
        guard let resolved = try? GroupUIContext.resolve(context, dataMode: groupsDataMode),
              let summaries = try? await groupsService.summaries(context: resolved) else { return nil }
        return Self.preferredGroup(in: summaries)
    }

    static func preferredGroup(in summaries: [GroupSummary]) -> GroupSummary? {
        summaries.filter { $0.missionID != nil }.min { lhs, rhs in
            !lhs.hasAnswered && rhs.hasAnswered
        } ?? summaries.first
    }
}
