import Foundation
import OpenRouter
import Testing

@testable import TagKit

struct SystemPromptTests {
    @Test func rendersStaticSectionsFirstAndTheEnvironmentLast() {
        let tool = ToolDefinition(
            name: "echo",
            description: "Echo the input back.",
            parameters: ["type": "object"],
            summary: "echo the input",
            guidelines: ["Use echo to test."],
        ) { $0 }
        var environment = SessionEnvironment.fake
        environment.projectInstructions = "\nRun make check.\n"

        let prompt = SystemPrompt.render(tools: [tool], environment: environment, model: "Scripted Model")

        #expect(prompt == Self.expectedPrompt)
    }

    static let expectedPrompt = """
        You are Tag, a coding agent in the user's terminal. You help with software tasks in one project: \
        you read and search its code, run commands and edit files.

        <tools>
        - echo: echo the input
        </tools>

        <rules>
        - Read the relevant code before changing it.
        - Change only what the task needs, and match the surrounding code's style.
        - After changing code, run the project's build or tests and read the result. If you couldn't, say so.
        - Ask before destructive or outward-facing actions (deleting files, git push, anything outside the \
        project), and when the request is ambiguous.
        - Finish with 2–4 sentences: what changed, how you checked it, what's left. Name files by path.
        - Use echo to test.
        </rules>

        <environment>
        Folder: /work/tag/
        OS: macOS 26.0.0 (arm64)
        Shell: bash 3.2.57(1)-release
        Git repository: yes
        Model: Scripted Model
        macOS ships BSD tools: use `sed -i ''` for in-place edits.
        </environment>

        <project_instructions path="AGENTS.md">
        Run make check.
        </project_instructions>
        """

    @Test func leavesOutEmptySectionsAndMacOSRules() {
        var environment = SessionEnvironment.fake
        environment.isMacOS = false
        environment.isGitRepository = false
        environment.projectInstructions = "  \n"

        let prompt = SystemPrompt.render(tools: [], environment: environment, model: "M")

        #expect(!prompt.contains("<tools>"))
        #expect(!prompt.contains("sed -i"))
        #expect(!prompt.contains("<project_instructions"))
        #expect(prompt.contains("Git repository: no"))
    }

    @Test func toolSummaryDefaultsToTheDescription() {
        #expect(echo.summary == "Echo the input")
        #expect(echo.guidelines.isEmpty)
    }

    @Test func everyBuiltInToolHasASummary() {
        let tools = ToolDefinition.builtIn(workingDirectory: URL(filePath: "/tmp"))
        #expect(tools.allSatisfy { $0.summary != $0.description })
    }

    @Test func probeReadsTheProjectAndTheMachine() async throws {
        let directory = try TemporaryDirectory()
        try directory.write("Be brief.", to: "AGENTS.md")

        let environment = await SessionEnvironment.probe(workingDirectory: directory.url)

        // No check of isGitRepository: inside git hooks GIT_DIR points at
        // Tag's repository, so even a temporary folder reports one.
        #expect(environment.workingDirectory == directory.url)
        #expect(environment.projectInstructions == "Be brief.")
        #expect(environment.shell.hasPrefix("bash "))
        #expect(!environment.operatingSystem.isEmpty)
    }

    @Test func formatsDatesInTheGivenCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(UserMessageDater.format(Date(timeIntervalSince1970: 0), calendar: calendar) == "1970-01-01")
    }
}
