public import Foundation
import ModelKit

/// Places Tag's tools stay out of: its own config directory, which holds the
/// user's API keys and ChatGPT tokens. It stops a model that was talked into
/// it (by a prompt injection in a file or a web page) from reading them with
/// the tools. It is a guard, not a sandbox: a shell command can still reach
/// the files in ways no check of the command's text sees.
public struct ProtectedPaths: Sendable {
    /// The directories that are off limits, with everything inside them:
    /// as given and with symbolic links resolved (`/var` is `/private/var`).
    public let directories: [URL]

    /// Creates a guard for `directories`.
    ///
    /// - Parameter directories: The directories that are off limits.
    public init(directories: [URL]) {
        var unique: [URL] = []
        for url in directories.flatMap({ [$0.standardizedFileURL, Self.resolved($0)] }) where !unique.contains(url) {
            unique.append(url)
        }
        self.directories = unique
    }

    /// Tag's config directory.
    public static let tagConfig = Self(directories: [ConfigDirectory.url()])

    /// Nothing is protected.
    public static let nothing = Self(directories: [])

    /// Throws when `url`, with symbolic links followed, is a protected
    /// directory or inside one.
    ///
    /// - Throws: A ``ToolError`` saying why.
    func check(_ url: URL) throws {
        let path = Self.resolved(url).path(percentEncoded: false).trimmingSuffix("/")
        for directory in directories {
            let protected = directory.path(percentEncoded: false).trimmingSuffix("/")
            if path == protected || path.hasPrefix(protected + "/") {
                throw refusal(directory)
            }
        }
    }

    /// Throws when `command` names a protected directory, however it is
    /// spelled (`/Users/me/.config/tag`, `~/.config/tag`, `$HOME/.config/tag`,
    /// `.config/tag`).
    ///
    /// - Throws: A ``ToolError`` saying why.
    func check(command: String) throws {
        for directory in directories {
            for spelling in Self.spellings(of: directory) where command.contains(spelling) {
                throw refusal(directory)
            }
        }
    }

    private func refusal(_ directory: URL) -> ToolError {
        ToolError(
            "refused: \(StatusLine.folder(directory)) is Tag's own config directory and holds the user's "
                + "credentials; the tools don't read or change it. Ask the user if they need something there.")
    }

    /// The ways a command can name `directory`: its path, from `~` or
    /// `$HOME`, and relative to the home directory.
    static func spellings(
        of directory: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String] {
        let path = directory.path(percentEncoded: false).trimmingSuffix("/")
        let homePath = resolved(home).path(percentEncoded: false).trimmingSuffix("/")
        guard path.hasPrefix(homePath + "/") else {
            return [path]
        }
        let relative = String(path.dropFirst(homePath.count + 1))
        return [path, "~/" + relative, "$HOME/" + relative, "${HOME}/" + relative, relative]
    }

    /// `url` made absolute, with `..` and symbolic links resolved.
    static func resolved(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

extension String {
    /// The string without one trailing `suffix`.
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}
