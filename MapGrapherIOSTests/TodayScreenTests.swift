import UIKit
import XCTest
@testable import MapGrapherIOS

final class TodayWeekTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testWeekStartsOnMondayEvenWhenTodayIsSunday() {
        // 2026-11-08は日曜日
        let monday = TodayWeek.monday(of: date(2026, 11, 8), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: monday), 2)
        XCTAssertEqual(calendar.component(.weekday, from: monday), 2)
    }

    func testDaysMarkPostedTodayAndFuture() {
        let today = date(2026, 11, 4)
        let thursday = calendar.startOfDay(for: date(2026, 11, 5))
        let monday = calendar.startOfDay(for: date(2026, 11, 2))
        let days = TodayWeek.days(today: today, posted: [monday], calendar: calendar)

        XCTAssertEqual(days.map(\.dayOfMonth), [2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(days[0].status, .posted)
        XCTAssertEqual(days[1].status, .past)
        XCTAssertEqual(days[2].status, .today)
        XCTAssertTrue(days[2].isToday)
        XCTAssertEqual(days.first { $0.date == thursday }?.status, .future)
    }

    func testPostedTodayStaysPostedAndKeepsTodayFlag() {
        let today = date(2026, 11, 4)
        let days = TodayWeek.days(today: today, posted: [calendar.startOfDay(for: today)], calendar: calendar)
        XCTAssertEqual(days[2].status, .posted)
        XCTAssertTrue(days[2].isToday)
    }

    func testHoursLeftRoundsDownAndTurnsSoonInLastHour() {
        XCTAssertEqual(TodayWeek.hoursLeft(now: date(2026, 11, 4, 10, 30), calendar: calendar), 13)
        XCTAssertNil(TodayWeek.hoursLeft(now: date(2026, 11, 4, 23, 30), calendar: calendar))
    }
}

final class InkSplatFieldTests: XCTestCase {
    func testSameSeedDrawsSameShape() {
        let first = InkSplatField(width: 72, height: 42, seed: 7).coverage(progress: 1).alpha
        let second = InkSplatField(width: 72, height: 42, seed: 7).coverage(progress: 1).alpha
        XCTAssertEqual(first, second)
    }

    func testDifferentSeedsDrawDifferentShapes() {
        let first = InkSplatField(width: 72, height: 42, seed: 7).coverage(progress: 1).alpha
        let second = InkSplatField(width: 72, height: 42, seed: 8).coverage(progress: 1).alpha
        XCTAssertNotEqual(first, second)
    }

    func testSplashGrowsAsProgressAdvances() {
        let field = InkSplatField(width: 90, height: 60, seed: 3)
        let start = field.coverage(progress: 0).alpha.reduce(0, +)
        let middle = field.coverage(progress: 0.5).alpha.reduce(0, +)
        let end = field.coverage(progress: 1).alpha
        XCTAssertGreaterThan(middle, start)
        XCTAssertGreaterThan(end.reduce(0, +), middle)
        XCTAssertTrue(end.allSatisfy { (0...1).contains($0) })
    }

    func testImageHasRequestedPixelSize() {
        let image = InkSplatField(width: 40, height: 30, seed: 1).image(progress: 1, color: .red)
        XCTAssertEqual(image?.width, 40)
        XCTAssertEqual(image?.height, 30)
    }
}
