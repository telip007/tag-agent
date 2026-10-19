import Foundation
import Testing

@testable import ModelKit

struct ResponsesErrorTests {
    @Test func tellsTheUserWhatToDoAboutPlanErrors() throws {
        let usage = ResponsesError.from(
            status: 429, body: #"{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"M"}}"#,
            provider: .codex)
        #expect(usage.provider == .codex)
        #expect(usage.errorDescription == "ChatGPT (Codex) usage limit reached. M")
        #expect(try #require(usage.recoverySuggestion).contains("https://chatgpt.com/settings/usage"))
        let errors: [ProviderError] = [
            .notConnected(.codex), .signInRequired(.codex, detail: "M"), .notEligible(.codex, detail: "M"),
            .unsupported(.codex, detail: "M"), .unavailable(.codex, detail: "M"),
            .http(.codex, status: 500, detail: "M"),
            .malformedResponse(.codex, detail: "M"), .usageLimit(.codex, detail: "M", manageURL: nil),
            .unknownModel(ModelRef(provider: .codex, model: "x")),
        ]
        for error in errors {
            #expect(error.provider == .codex)
            #expect(error.errorDescription?.isEmpty == false)
            _ = error.recoverySuggestion
        }
    }

    @Test func mapsChatGPTPlanErrorCodes() {
        func map(_ status: Int, _ body: String) -> ProviderError {
            ResponsesError.from(status: status, body: body, provider: .codex)
        }
        func body(_ code: String, param: String? = nil) -> String {
            let param = param.map { #","param":"\#($0)""# } ?? ""
            return #"{"error":{"code":"\#(code)","message":"M"\#(param)}}"#
        }
        #expect(map(503, body("subscription_sharing_usage_unavailable")) == .unavailable(.codex, detail: "M"))
        #expect(map(503, body("subscription_sharing_user_unavailable")) == .unavailable(.codex, detail: "M"))
        #expect(map(403, body("subscription_sharing_user_not_eligible")) == .notEligible(.codex, detail: "M"))
        #expect(
            map(400, body("subscription_sharing_unsupported_capability", param: "tools"))
                == .unsupported(.codex, detail: "M (tools)"))
        #expect(map(401, body("subscription_sharing_invalid_user")) == .signInRequired(.codex, detail: "M"))
        #expect(
            map(403, body("chatpass_v2_scope_not_authorized"))
                == .http(.codex, status: 403, detail: "M (chatpass_v2_scope_not_authorized)"))
        #expect(map(403, #"{"detail":"Region."}"#) == .http(.codex, status: 403, detail: "Region."))
        #expect(map(503, "Down") == .unavailable(.codex, detail: "Down"))
        #expect(map(500, #"{"error":"Broken"}"#) == .http(.codex, status: 500, detail: "Broken"))
    }
}
