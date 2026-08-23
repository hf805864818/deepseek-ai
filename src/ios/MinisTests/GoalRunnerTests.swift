import XCTest
@testable import Minis

/// Layer C contract tests: `GoalRunner.parse` must turn the trailing
/// `<<GOAL_STATE>>` sentinel into a deterministic, fail-safe decision.
///
/// These tests pin the parsing semantics that the auto-continue hook
/// (`maybeAutoContinueGoal`) relies on, so a future refactor of the sentinel
/// grammar cannot silently break "auto-continue on pending, stop on done".
final class GoalRunnerTests: XCTestCase {

    // MARK: - done sentinel

    func testDone() {
        XCTAssertEqual(GoalRunner.parse("<<GOAL_STATE>> done"), .done)
    }

    func testDoneTrailingWhitespace() {
        XCTAssertEqual(GoalRunner.parse("<<GOAL_STATE>> done\n\n"), .done)
    }

    func testDoneMixedCaseToken() {
        XCTAssertEqual(GoalRunner.parse("<<GOAL_STATE>> Done"), .done)
    }

    // MARK: - pending sentinel

    func testPendingWithReason() {
        XCTAssertEqual(
            GoalRunner.parse("<<GOAL_STATE>> pending: 执行第二步"),
            .pending(reason: "执行第二步")
        )
    }

    func testPendingNoReason() {
        XCTAssertEqual(GoalRunner.parse("<<GOAL_STATE>> pending"), .pending(reason: nil))
    }

    func testPendingColonOnly() {
        XCTAssertEqual(GoalRunner.parse("<<GOAL_STATE>> pending:"), .pending(reason: nil))
    }

    func testPendingChineseColonReason() {
        XCTAssertEqual(
            GoalRunner.parse("<<GOAL_STATE>> pending：继续处理清单"),
            .pending(reason: "继续处理清单")
        )
    }

    func testPendingDashTrimmedReason() {
        XCTAssertEqual(
            GoalRunner.parse("<<GOAL_STATE>> pending: - 执行下一个子任务"),
            .pending(reason: "执行下一个子任务")
        )
    }

    // MARK: - fail-safe (no continuation)

    func testNoSentinelReturnsNil() {
        XCTAssertNil(GoalRunner.parse("任务已完成，无需继续。"))
    }

    func testUnrecognizedTokenReturnsNil() {
        XCTAssertNil(GoalRunner.parse("<<GOAL_STATE>> banana"))
    }

    // MARK: - marker robustness

    func testCaseInsensitiveMarker() {
        XCTAssertEqual(GoalRunner.parse("<<goal_state>> done"), .done)
    }

    func testLastOccurrenceWins() {
        let text = "先说 <<GOAL_STATE>> pending: 第一步\n"
                 + "…中间内容…\n"
                 + "<<GOAL_STATE>> done"
        XCTAssertEqual(GoalRunner.parse(text), .done)
    }

    // MARK: - cap contract

    func testMaxAutoRoundsContract() {
        // The auto-continue budget must stay a small, bounded number so a
        // single user prompt can never loop forever.
        XCTAssertEqual(GoalRunner.maxAutoRounds, 3)
    }
}