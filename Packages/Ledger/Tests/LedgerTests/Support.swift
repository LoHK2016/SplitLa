import Foundation
@testable import Ledger

let hongKong: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
    return calendar
}()

func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    hongKong.date(from: DateComponents(year: year, month: month, day: day, hour: 20))!
}

func cents(_ value: Int) -> Money { Money(cents: value) }
func dollars(_ value: Int) -> Money { Money(dollars: value) }

let amy: MemberID = "amy"
let ben: MemberID = "ben"
let cat: MemberID = "cat"
let dan: MemberID = "dan"
let eve: MemberID = "eve"

func members(_ ids: MemberID...) -> [Member] { ids.map { Member(id: $0, name: $0.rawValue) } }

func expense(
    _ id: ExpenseID, in activity: ActivityID = "dinner", on date: Date = day(2026, 12, 5),
    _ amount: Money, paidBy: MemberID, among: Set<MemberID>, serviceCharge: Bool = false
) -> Expense {
    try! Expense(
        id: id, activityID: activity, title: id.rawValue, date: date, amount: amount,
        paidBy: paidBy, split: .equal(among: among), hasServiceCharge: serviceCharge
    )
}

func going(_ ids: MemberID...) -> [MemberID: Attendance] {
    Dictionary(uniqueKeysWithValues: ids.map { ($0, Attendance.going) })
}
