import Foundation

/// Structured diagnostics for a signing operation. Kept separate from UI so
/// bulk and single-app signing can present the same safety information.
struct SigningReport: Codable {
    let appIdentifier: String?
    let outputIdentifier: String?
    let certificateName: String?
    let completedAt: Date
    let warnings: [String]
    let succeeded: Bool
}
