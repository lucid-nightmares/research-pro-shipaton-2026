import XCTest
@testable import ResearchOSFlightRecorder

@MainActor
final class LibrarySearchTests: XCTestCase {
    private func project(_ id: String, title: String, question: String, updated: TimeInterval) -> ResearchProject {
        var value = ResearchProject.blank(title: title, question: question, id: UUID(uuidString: id)!, now: Date(timeIntervalSince1970: 1_800_000_000), makeUUID: UUID.init)
        value.updatedAt = Date(timeIntervalSince1970: updated)
        return value
    }

    func testAccentAndCaseInsensitiveTitleSearchAndQuestionSearch() {
        let titleMatch = project("00000000-0000-0000-0000-000000000001", title: "École observations", question: "What happened?", updated: 1)
        let questionMatch = project("00000000-0000-0000-0000-000000000002", title: "Study B", question: "What predicts RÉCALL?", updated: 2)
        XCTAssertEqual(ResearchProjectList.filtered([titleMatch, questionMatch], query: "ecole").map(\.id), [titleMatch.id])
        XCTAssertEqual(ResearchProjectList.filtered([titleMatch, questionMatch], query: "recall").map(\.id), [questionMatch.id])
        XCTAssertEqual(ResearchProjectList.filtered([titleMatch, questionMatch], query: "  ÉCOLE \n").map(\.id), [titleMatch.id])
    }

    func testWhitespaceQueryReturnsAllProjectsNewestFirstWithoutMutatingInput() {
        let old = project("00000000-0000-0000-0000-000000000001", title: "Older", question: "Q1", updated: 1)
        let new = project("00000000-0000-0000-0000-000000000002", title: "Newer", question: "Q2", updated: 10)
        let input = [old, new]
        XCTAssertEqual(ResearchProjectList.filtered(input, query: " \n\t ").map(\.id), [new.id, old.id])
        XCTAssertEqual(input, [old, new])
    }

    func testEqualUpdateTimesHaveStableIdentityOrderIndependentOfInputOrder() {
        let first = project("00000000-0000-0000-0000-000000000001", title: "Same", question: "Q", updated: 10)
        let second = project("00000000-0000-0000-0000-000000000002", title: "Same", question: "Q", updated: 10)
        XCTAssertEqual(ResearchProjectList.filtered([second, first], query: "Same").map(\.id), [first.id, second.id])
        XCTAssertEqual(ResearchProjectList.filtered([first, second], query: "Same").map(\.id), [first.id, second.id])
    }

    func testUnmatchedQueryAndEmptyScopeReturnNoProjects() {
        let item = project("00000000-0000-0000-0000-000000000001", title: "Observation", question: "One class", updated: 1)
        XCTAssertTrue(ResearchProjectList.filtered([item], query: "unmatched query").isEmpty)
        XCTAssertTrue(ResearchProjectList.filtered([], query: "Observation").isEmpty)
    }
}
