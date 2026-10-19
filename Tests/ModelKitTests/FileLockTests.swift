import Foundation
import Synchronization
import Testing

@testable import ModelKit

struct FileLockTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "tag-tests-\(UUID().uuidString)/.lock")

    @Test func aSecondHolderWaitsUntilTheFirstLetsGo() async throws {
        let order = Mutex<[String]>([])
        let first = FileLock(url: url)
        let second = FileLock(url: url)
        try await first.waitingWithLock {
            let waiting = Task {
                try await second.waitingWithLock { order.withLock { $0.append("second") } }
            }
            try await Task.sleep(for: .milliseconds(100))
            order.withLock { $0.append("first") }
            return waiting
        }
        .value
        #expect(order.withLock { $0 } == ["first", "second"])
    }

    @Test func theBlockingLockExcludesTheWaitingOne() async throws {
        let lock = FileLock(url: url)
        let held = try lock.withLock { 1 }
        #expect(held == 1)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(try await lock.waitingWithLock { 2 } == 2)
    }

    @Test func concurrentStoreUpdatesKeepEveryChange() async throws {
        let directory = url.deletingLastPathComponent()
        let stores = (0..<2).map { _ in CredentialStore(directory: directory, environment: [:]) }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    try? stores[index % 2].setAPIKey(
                        "key-\(index)", for: index.isMultiple(of: 2) ? .openRouter : .openCodeGo)
                    try? stores[index % 2].update { $0.apiKeys["n\(index)"] = "\(index)" }
                }
            }
        }
        #expect(stores[0].load().apiKeys.count == 42)
    }
}
