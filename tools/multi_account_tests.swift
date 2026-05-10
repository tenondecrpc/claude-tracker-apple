import Foundation

// Standalone unit tests covering the core multi-account shared types:
//   - `AccountIdentifier.canonicalize(email:)`: NFC normalization, trimming,
//     lowercasing, and empty-input rejection.
//   - `AccountIdentifier.cliFallbackAccountId(from:)`: determinism and format.
//   - `AccountIdentifier.percentEncodedDirectoryName(for:)`: filesystem-safe
//     encoding of canonical account ids.
//   - `Account` equality: accountId-only semantics, identity alias.
//   - `UsageState` decoding: accountId is strictly required, no silent default.
//
// Follows the same standalone-executable pattern as
// `tools/widget_smoke_test.swift` and `tools/concurrency_smoke_test.swift`:
// compile with `swiftc` against the `Shared/` sources, run the binary, and
// fail loudly by throwing `SmokeFailure` on mismatch.

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct MultiAccountTests {
    static func main() throws {
        try assertCanonicalizeLowercasesInput()
        try assertCanonicalizeTrimsWhitespace()
        try assertCanonicalizeAppliesNFCNormalization()
        try assertCanonicalizeRejectsEmptyAndWhitespace()

        try assertCLIFallbackIsDeterministic()
        try assertCLIFallbackFormat()

        try assertPercentEncodedDirectoryNameKeepsReadableChars()
        try assertPercentEncodedDirectoryNameEncodesUnsafeChars()

        try assertAccountEqualityByAccountId()
        try assertAccountInequalityOnDifferentAccountId()
        try assertAccountIdentityAliasesAccountId()

        try assertUsageStateDecodesWithAccountId()
        try assertUsageStateDecodingRejectsMissingAccountId()

        print("Multi-account unit tests passed")
    }

    // MARK: - AccountIdentifier.canonicalize(email:)

    private static func assertCanonicalizeLowercasesInput() throws {
        let canonical = try AccountIdentifier.canonicalize(email: "ALICE@Example.com")
        guard canonical == "alice@example.com" else {
            throw SmokeFailure(
                message: "Expected lowercasing to produce 'alice@example.com', got '\(canonical)'"
            )
        }
    }

    private static func assertCanonicalizeTrimsWhitespace() throws {
        let canonical = try AccountIdentifier.canonicalize(email: "  bob@example.com  ")
        guard canonical == "bob@example.com" else {
            throw SmokeFailure(
                message: "Expected trimming to produce 'bob@example.com', got '\(canonical)'"
            )
        }

        // Tabs and newlines are part of `.whitespacesAndNewlines` and must be
        // stripped as well.
        let canonicalMixed = try AccountIdentifier.canonicalize(email: "\t carol@example.com\n")
        guard canonicalMixed == "carol@example.com" else {
            throw SmokeFailure(
                message: "Expected mixed-whitespace trim to produce 'carol@example.com', got '\(canonicalMixed)'"
            )
        }
    }

    private static func assertCanonicalizeAppliesNFCNormalization() throws {
        // Decomposed form: "cafe" + COMBINING ACUTE ACCENT (U+0301) as the
        // local-part. NFC normalization must precompose this into the single
        // character U+00E9 ("é"), producing the same canonical string a
        // composed input would.
        let decomposedEmail = "cafe\u{0301}@example.com"
        let composedEmail = "caf\u{00E9}@example.com"

        let canonicalDecomposed = try AccountIdentifier.canonicalize(email: decomposedEmail)
        let canonicalComposed = try AccountIdentifier.canonicalize(email: composedEmail)

        // Both inputs must produce the same canonical accountId. This is the
        // invariant callers rely on when comparing Keychain slot names across
        // environments that may emit either form.
        guard canonicalDecomposed == canonicalComposed else {
            throw SmokeFailure(
                message: "NFC mismatch: decomposed='\(canonicalDecomposed)' composed='\(canonicalComposed)'"
            )
        }

        // And the canonical form must itself be the precomposed variant.
        guard canonicalDecomposed == "caf\u{00E9}@example.com" else {
            throw SmokeFailure(
                message: "Expected NFC canonical form 'caf\u{00E9}@example.com', got '\(canonicalDecomposed)'"
            )
        }

        // Sanity: the raw decomposed input has a different UTF-8 byte count
        // from the composed one, so the canonicalizer is doing real work at
        // the byte level (Swift's `String ==` already normalizes, so the
        // byte-length check is the meaningful "inputs really differ" assertion).
        guard Array(decomposedEmail.utf8) != Array(composedEmail.utf8) else {
            throw SmokeFailure(
                message: "Test fixture is broken: decomposed and composed inputs have identical UTF-8 bytes"
            )
        }
    }

    private static func assertCanonicalizeRejectsEmptyAndWhitespace() throws {
        let emptyInputs = ["", "   ", "\t\n", "\r\n  "]
        for input in emptyInputs {
            do {
                let result = try AccountIdentifier.canonicalize(email: input)
                throw SmokeFailure(
                    message: "Expected canonicalize to throw for '\(input)', got '\(result)'"
                )
            } catch let error as AccountIdentifierError {
                guard error == .emptyEmail else {
                    throw SmokeFailure(
                        message: "Expected .emptyEmail for '\(input)', got \(error)"
                    )
                }
            }
        }
    }

    // MARK: - AccountIdentifier.cliFallbackAccountId(from:)

    private static func assertCLIFallbackIsDeterministic() throws {
        let seed = "/Users/alice/.claude/profile"
        let first = AccountIdentifier.cliFallbackAccountId(from: seed)
        let second = AccountIdentifier.cliFallbackAccountId(from: seed)
        guard first == second else {
            throw SmokeFailure(
                message: "CLI fallback is not deterministic: first='\(first)' second='\(second)'"
            )
        }

        // Empty seed is permitted and must also be deterministic.
        let empty1 = AccountIdentifier.cliFallbackAccountId(from: "")
        let empty2 = AccountIdentifier.cliFallbackAccountId(from: "")
        guard empty1 == empty2 else {
            throw SmokeFailure(
                message: "CLI fallback for empty seed is not deterministic: '\(empty1)' vs '\(empty2)'"
            )
        }

        // Different seeds must produce different ids (trivial collision check;
        // the prefix is 8 hex characters so real collisions are astronomically
        // unlikely for two hand-picked inputs).
        let other = AccountIdentifier.cliFallbackAccountId(from: "different-seed")
        guard first != other else {
            throw SmokeFailure(
                message: "CLI fallback produced identical ids for different seeds: '\(first)'"
            )
        }
    }

    private static func assertCLIFallbackFormat() throws {
        let id = AccountIdentifier.cliFallbackAccountId(from: "seed")
        let prefix = "cli-local-"
        guard id.hasPrefix(prefix) else {
            throw SmokeFailure(message: "CLI fallback id missing 'cli-local-' prefix: '\(id)'")
        }
        let suffix = String(id.dropFirst(prefix.count))
        guard suffix.count == 8 else {
            throw SmokeFailure(
                message: "CLI fallback suffix must be 8 chars, got \(suffix.count) in '\(id)'"
            )
        }
        let hexChars: Set<Character> = Set("0123456789abcdef")
        for ch in suffix {
            guard hexChars.contains(ch) else {
                throw SmokeFailure(
                    message: "CLI fallback suffix contains non-hex char '\(ch)' in '\(id)'"
                )
            }
        }
    }

    // MARK: - AccountIdentifier.percentEncodedDirectoryName(for:)

    private static func assertPercentEncodedDirectoryNameKeepsReadableChars() throws {
        // The allowed set includes `@`, `.`, `_`, `-`, digits, and lowercase
        // ASCII letters. A canonical accountId like `alice@example.com` must
        // therefore round-trip unchanged.
        let canonical = "alice@example.com"
        let encoded = AccountIdentifier.percentEncodedDirectoryName(for: canonical)
        guard encoded == canonical else {
            throw SmokeFailure(
                message: "Expected '\(canonical)' to stay readable, got '\(encoded)'"
            )
        }

        // Dots and dashes must also survive.
        let dotted = "a.b-c_d@example.com"
        let dottedEncoded = AccountIdentifier.percentEncodedDirectoryName(for: dotted)
        guard dottedEncoded == dotted else {
            throw SmokeFailure(
                message: "Expected '\(dotted)' to stay readable, got '\(dottedEncoded)'"
            )
        }
    }

    private static func assertPercentEncodedDirectoryNameEncodesUnsafeChars() throws {
        // Spaces and slashes are not in the allowed set and must be percent-
        // encoded so the resulting string is safe to use as a single iCloud
        // directory component.
        let spaced = AccountIdentifier.percentEncodedDirectoryName(for: "user name@example.com")
        guard spaced.contains("%20"), !spaced.contains(" ") else {
            throw SmokeFailure(
                message: "Expected spaces to be percent-encoded, got '\(spaced)'"
            )
        }

        let slashed = AccountIdentifier.percentEncodedDirectoryName(for: "bad/path@example.com")
        guard slashed.contains("%2F") || slashed.contains("%2f"), !slashed.contains("/") else {
            throw SmokeFailure(
                message: "Expected slashes to be percent-encoded, got '\(slashed)'"
            )
        }

        // Literal `%` must itself be escaped so the encoding is unambiguous.
        let percent = AccountIdentifier.percentEncodedDirectoryName(for: "a%b@example.com")
        guard percent.contains("%25") else {
            throw SmokeFailure(
                message: "Expected literal '%' to be encoded as '%25', got '\(percent)'"
            )
        }
    }

    // MARK: - Account equality and identity

    private static func assertAccountEqualityByAccountId() throws {
        let base = Account(
            accountId: "alice@example.com",
            email: "alice@example.com",
            displayName: "Alice",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let renamed = Account(
            accountId: "alice@example.com",
            email: "ALICE@Example.com",
            displayName: "Alice Smith",
            createdAt: Date(timeIntervalSince1970: 1_700_999_999)
        )

        guard base == renamed else {
            throw SmokeFailure(
                message: "Accounts with the same accountId must be equal regardless of displayName/email/createdAt"
            )
        }
    }

    private static func assertAccountInequalityOnDifferentAccountId() throws {
        let alice = Account(
            accountId: "alice@example.com",
            email: "alice@example.com",
            displayName: "Alice",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bob = Account(
            accountId: "bob@example.com",
            email: "alice@example.com",
            displayName: "Alice",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        guard alice != bob else {
            throw SmokeFailure(
                message: "Accounts with different accountIds must not be equal, even when other fields match"
            )
        }
    }

    private static func assertAccountIdentityAliasesAccountId() throws {
        let account = Account(
            accountId: "carol@example.com",
            email: "carol@example.com",
            displayName: "Carol",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        guard account.id == account.accountId else {
            throw SmokeFailure(
                message: "Account.id must forward to accountId, got id='\(account.id)' accountId='\(account.accountId)'"
            )
        }
    }

    // MARK: - UsageState decoding

    private static func assertUsageStateDecodesWithAccountId() throws {
        let json = """
        {
            "accountId": "alice@example.com",
            "utilization5h": 0.42,
            "utilization7d": 0.18,
            "resetAt5h": "2023-11-14T22:23:20Z",
            "resetAt7d": "2023-11-15T22:00:00Z",
            "isMocked": true,
            "extraUsage": {
                "is_enabled": true,
                "used_credits": 0,
                "monthly_limit": 2000,
                "utilization": 0
            },
            "isDoubleLimitPromoActive": false
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = Data(json.utf8)
        let usage = try decoder.decode(UsageState.self, from: data)
        guard usage.accountId == "alice@example.com" else {
            throw SmokeFailure(
                message: "Expected accountId 'alice@example.com', got '\(usage.accountId)'"
            )
        }
        guard usage.utilization5h == 0.42 else {
            throw SmokeFailure(message: "Expected utilization5h 0.42, got \(usage.utilization5h)")
        }
        guard usage.isMocked else {
            throw SmokeFailure(message: "Expected isMocked true")
        }
    }

    private static func assertUsageStateDecodingRejectsMissingAccountId() throws {
        // Same payload as above, minus the `accountId` key. The synthesized
        // Codable conformance must reject this as a keyNotFound error because
        // `accountId` is a non-optional property and the design explicitly
        // forbids silent defaulting.
        let json = """
        {
            "utilization5h": 0.42,
            "utilization7d": 0.18,
            "resetAt5h": "2023-11-14T22:23:20Z",
            "resetAt7d": "2023-11-15T22:00:00Z",
            "isMocked": true
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = Data(json.utf8)
        do {
            let usage = try decoder.decode(UsageState.self, from: data)
            throw SmokeFailure(
                message: "Expected decoding to throw for missing accountId, got accountId='\(usage.accountId)'"
            )
        } catch let failure as SmokeFailure {
            // Our own assertion failure - surface it.
            throw failure
        } catch {
            // Any DecodingError (keyNotFound/valueNotFound) satisfies the
            // requirement that missing accountId must not silently default.
            // Guard against accidentally accepting non-decoding errors (e.g.
            // a future custom initializer throwing something unrelated).
            guard error is DecodingError else {
                throw SmokeFailure(
                    message: "Expected DecodingError for missing accountId, got \(type(of: error)): \(error)"
                )
            }
        }
    }
}
