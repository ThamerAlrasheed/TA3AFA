import Foundation

struct ScanTextResolverResponse: Codable, Hashable {
    var bestMatchMedicationId: String?
    var confidence: String
    var reason: String
    var missingOrUncertainFields: [String]
    var requiresUserConfirmation: Bool
    var needsFallback: Bool
    var fallbackReason: String?
}

protocol ScanTextResolving {
    func resolve(decision: MedicationScanDecision) async throws -> ScanTextResolverResponse
}

final class ScanTextResolverClient: ScanTextResolving {
    private struct Request: Encodable {
        let scanSessionId: String
        let ocrText: String
        let extractedFields: MedicationExtractedFields
        let databaseCandidates: [MedicationScanCandidate]
        let userLocale: String
    }

    func resolve(decision: MedicationScanDecision) async throws -> ScanTextResolverResponse {
        let locale = UserDefaults.standard.string(forKey: "appearance.language") ?? Locale.current.language.languageCode?.identifier ?? "en"
        var headers = [
            "apikey": SupabaseManager.shared.supabaseKey,
            "Content-Type": "application/json"
        ]
        if let accessToken = SupabaseManager.shared.client.auth.currentSession?.accessToken {
            headers["Authorization"] = "Bearer \(accessToken)"
        }

        return try await SupabaseManager.shared.client.functions.invoke(
            "scan-text-resolver",
            options: .init(
                method: .post,
                headers: headers,
                body: Request(
                    scanSessionId: decision.scanSessionId.uuidString,
                    ocrText: decision.ocrResult.rawText,
                    extractedFields: decision.extractedFields,
                    databaseCandidates: decision.candidates,
                    userLocale: locale
                )
            )
        )
    }
}
