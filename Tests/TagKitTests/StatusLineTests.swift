import Foundation
import Testing

@testable import TagKit

struct StatusLineTests {
    private let directory = URL(filePath: "/work/tag", directoryHint: .isDirectory)

    private func status(
        name: String = "DeepSeek V4.1 Flash",
        contextLength: Int? = 200_000,
        contextTokens: Int = 0,
        cost: Double = 0,
    ) -> StatusLine {
        StatusLine(
            directory: directory,
            model: ModelDescription(name: name, contextLength: contextLength),
            contextTokens: contextTokens,
            cost: cost,
        )
    }

    @Test func showsFolderModelContextAndCost() {
        let line = status(contextTokens: 12_345, cost: 0.0012)
        #expect(line.text == "/work/tag · DeepSeek V4.1 Flash · ctx 12.3k/200k (6%) · $0.0012")
    }

    @Test func showsZeroBeforeTheFirstReply() {
        #expect(status().text == "/work/tag · DeepSeek V4.1 Flash · ctx 0/200k (0%) · $0.00")
    }

    @Test func omitsTheWindowWhenTheCatalogueDoesNotKnowIt() {
        let text = status(name: "deepseek/deepseek-v4.1-flash", contextLength: nil, contextTokens: 999).text
        #expect(text == "/work/tag · deepseek/deepseek-v4.1-flash · ctx 999 · $0.00")
    }

    @Test(arguments: [
        (1_500_000, "1.5M"),
        (1_000_000, "1M"),
        (64_000, "64k"),
        (1_200, "1.2k"),
        (999, "999"),
    ])
    func roundsTokenCounts(count: Int, expected: String) {
        #expect(status(contextLength: nil, contextTokens: count).text.hasSuffix("ctx \(expected) · $0.00"))
    }

    @Test(arguments: [
        (0.0, "$0.00"),
        (1.5, "$1.50"),
        (0.0125, "$0.0125"),
        (0.0012, "$0.0012"),
        (0.000123, "$0.000123"),
    ])
    func formatsCost(cost: Double, expected: String) {
        #expect(status(contextLength: nil, cost: cost).text.hasSuffix("· \(expected)"))
    }

    @Test func shortensTheHomeDirectory() {
        let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)
        #expect(StatusLine.folder(home, home: home) == "~")
        #expect(StatusLine.folder(URL(filePath: "/Users/me/dev/tag"), home: home) == "~/dev/tag")
        #expect(StatusLine.folder(URL(filePath: "/Users/melon/tag"), home: home) == "/Users/melon/tag")
        #expect(StatusLine.folder(URL(filePath: "/opt/tag"), home: home) == "/opt/tag")
    }
}
