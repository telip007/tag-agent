public import Foundation

/// What the system prompt says about the machine and the project. Probed
/// once at startup and never changed during a session, so the rendered
/// prompt stays a stable, cacheable prefix. See wiki/concepts/system-prompt.md.
public struct SessionEnvironment: Sendable, Equatable {
    /// The project folder the tools work in.
    public var workingDirectory: URL
    /// The operating system and its version, e.g. `"macOS 26.0.1"`.
    public var operatingSystem: String
    /// The CPU architecture, e.g. `"arm64"`.
    public var architecture: String
    /// Whether the machine runs macOS, whose BSD tools differ from GNU ones.
    public var isMacOS: Bool
    /// The shell the `bash` tool runs, e.g. `"bash 3.2.57"`.
    public var shell: String
    /// Whether the working directory is inside a git repository.
    public var isGitRepository: Bool
    /// The contents of `AGENTS.md` in the working directory, if there is one.
    public var projectInstructions: String?

    /// Creates an environment from known values, e.g. a fake one in tests.
    public init(
        workingDirectory: URL,
        operatingSystem: String,
        architecture: String,
        isMacOS: Bool,
        shell: String,
        isGitRepository: Bool,
        projectInstructions: String? = nil,
    ) {
        self.workingDirectory = workingDirectory
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.isMacOS = isMacOS
        self.shell = shell
        self.isGitRepository = isGitRepository
        self.projectInstructions = projectInstructions
    }

    /// The file whose contents become the project instructions.
    static let projectInstructionsFile = "AGENTS.md"

    /// Probes the machine and the project in `workingDirectory`.
    public static func probe(workingDirectory: URL) async -> Self {
        #if os(macOS)
        let (name, isMacOS) = ("macOS", true)
        #else
        let (name, isMacOS) = ("Linux", false)
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let bashVersion = await output(of: "bash", ["-c", "echo $BASH_VERSION"], in: workingDirectory)
        let insideGit = await output(of: "git", ["rev-parse", "--is-inside-work-tree"], in: workingDirectory)
        let instructions = try? String(
            contentsOf: workingDirectory.appending(path: projectInstructionsFile),
            encoding: .utf8,
        )
        return Self(
            workingDirectory: workingDirectory,
            operatingSystem: "\(name) \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: architecture,
            isMacOS: isMacOS,
            shell: bashVersion.map { "bash \($0)" } ?? "bash",
            isGitRepository: insideGit == "true",
            projectInstructions: instructions,
        )
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    /// A program's trimmed output, or `nil` when it fails or prints nothing.
    private static func output(of program: String, _ arguments: [String], in directory: URL) async -> String? {
        guard let result = try? await ProcessRunner.run(program, arguments, in: directory), result.status == 0 else {
            return nil
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}

/// Renders the system prompt: static sections first, the session's
/// environment last, so the start of the prompt is the same in every session.
enum SystemPrompt {
    static func render(tools: [ToolDefinition], environment: SessionEnvironment, model: String) -> String {
        var sections = [
            """
            You are Tag, a coding agent in the user's terminal. You help with software \
            tasks in one project: you read and search its code, run commands and edit files.
            """
        ]
        if !tools.isEmpty {
            sections.append(tag("tools", tools.map { "- \($0.name): \($0.summary)" }))
        }
        sections.append(tag("rules", (rules + tools.flatMap(\.guidelines)).map { "- \($0)" }))
        sections.append(tag("environment", environmentLines(environment, model: model)))
        if let instructions = environment.projectInstructions?.trimmingCharacters(in: .whitespacesAndNewlines),
            !instructions.isEmpty
        {
            sections.append(
                """
                <project_instructions path="\(SessionEnvironment.projectInstructionsFile)">
                \(instructions)
                </project_instructions>
                """
            )
        }
        return sections.joined(separator: "\n\n")
    }

    /// Rules for every session, whatever the tools.
    static let rules = [
        "Read the relevant code before changing it.",
        "Change only what the task needs, and match the surrounding code's style.",
        "After changing code, run the project's build or tests and read the result. If you couldn't, say so.",
        """
        Ask before destructive or outward-facing actions (deleting files, git push, anything outside the \
        project), and when the request is ambiguous.
        """,
        "Finish with 2–4 sentences: what changed, how you checked it, what's left. Name files by path.",
    ]

    private static func environmentLines(_ environment: SessionEnvironment, model: String) -> [String] {
        var lines = [
            "Folder: \(environment.workingDirectory.path(percentEncoded: false))",
            "OS: \(environment.operatingSystem) (\(environment.architecture))",
            "Shell: \(environment.shell)",
            "Git repository: \(environment.isGitRepository ? "yes" : "no")",
            "Model: \(model)",
        ]
        if environment.isMacOS {
            lines.append("macOS ships BSD tools: use `sed -i ''` for in-place edits.")
        }
        return lines
    }

    private static func tag(_ name: String, _ lines: [String]) -> String {
        "<\(name)>\n\(lines.joined(separator: "\n"))\n</\(name)>"
    }
}

/// Puts today's date on user messages: on the first one, and whenever the
/// date changed since the last one. The date stays out of the system prompt
/// because a session can cross midnight.
struct UserMessageDater {
    private var lastDate: String?

    /// The user's text, preceded by the date when the model hasn't seen it.
    mutating func message(_ text: String, at now: Date, calendar: Calendar = .current) -> String {
        let date = Self.format(now, calendar: calendar)
        defer { lastDate = date }
        guard date != lastDate else {
            return text
        }
        return "<environment_update>date: \(date)</environment_update>\n\n\(text)"
    }

    /// `yyyy-MM-dd` in the calendar's time zone.
    static func format(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let (year, month, day) = (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        func padded(_ number: Int, _ width: Int) -> String {
            String(repeating: "0", count: max(0, width - "\(number)".count)) + "\(number)"
        }
        return "\(padded(year, 4))-\(padded(month, 2))-\(padded(day, 2))"
    }
}
