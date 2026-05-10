import Foundation

final class PatientSessionStore {
    static let shared = PatientSessionStore()

    enum SessionKey: String, CaseIterable {
        case deviceToken
        case patientUserID = "patientUserId"
        case activePatientID = "activePatientId"
        case activePatientName
        case userRole
    }

    private let keychain: KeychainService
    private let userDefaults: UserDefaults

    init(keychain: KeychainService = .shared, userDefaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.userDefaults = userDefaults
    }

    var patientUserID: UUID? {
        guard let raw = readString(.patientUserID) else { return nil }
        return UUID(uuidString: raw)
    }

    var patientUserIDString: String? {
        readString(.patientUserID)
    }

    var deviceToken: String? {
        readString(.deviceToken)
    }

    var activePatientID: UUID? {
        guard let raw = readString(.activePatientID) else { return nil }
        return UUID(uuidString: raw)
    }

    var activePatientName: String? {
        readString(.activePatientName)
    }

    var userRoleRawValue: String? {
        readString(.userRole)
    }

    @discardableResult
    func migrateLegacyUserDefaultsIfNeeded() throws -> [String] {
        var migratedKeys: [String] = []

        for key in SessionKey.allCases {
            guard let legacyValue = userDefaults.string(forKey: key.rawValue) else {
                continue
            }

            if !legacyValue.isEmpty, try keychain.string(forKey: key.rawValue) == nil {
                try keychain.setString(legacyValue, forKey: key.rawValue)
            }

            userDefaults.removeObject(forKey: key.rawValue)
            migratedKeys.append(key.rawValue)
        }

        return migratedKeys
    }

    func savePatientSession(patientID: String, deviceToken: String) throws {
        try setString(patientID, for: .patientUserID)
        try setString(deviceToken, for: .deviceToken)
    }

    func setActivePatientID(_ id: UUID?) throws {
        if let id {
            try setString(id.uuidString.lowercased(), for: .activePatientID)
        } else {
            try deleteString(.activePatientID)
        }
    }

    func setActivePatientName(_ name: String?) throws {
        if let name, !name.isEmpty {
            try setString(name, for: .activePatientName)
        } else {
            try deleteString(.activePatientName)
        }
    }

    func setUserRole(_ rawValue: String) throws {
        try setString(rawValue, for: .userRole)
    }

    func clearPatientSession() throws {
        try deleteString(.patientUserID)
        try deleteString(.deviceToken)
    }

    func clearUserRole() throws {
        try deleteString(.userRole)
    }

    func clearAllSessionValues() throws {
        for key in SessionKey.allCases {
            try deleteString(key)
        }
    }

    func clearAllSessionValuesBestEffort() {
        for key in SessionKey.allCases {
            do {
                try deleteString(key)
            } catch {
                logKeychainError(error, operation: "delete", key: key)
            }
        }
    }

    private func readString(_ key: SessionKey) -> String? {
        do {
            return try keychain.string(forKey: key.rawValue)
        } catch {
            logKeychainError(error, operation: "read", key: key)
            return nil
        }
    }

    private func setString(_ value: String, for key: SessionKey) throws {
        do {
            try keychain.setString(value, forKey: key.rawValue)
        } catch {
            logKeychainError(error, operation: "write", key: key)
            throw error
        }
    }

    private func deleteString(_ key: SessionKey) throws {
        do {
            try keychain.deleteString(forKey: key.rawValue)
        } catch {
            logKeychainError(error, operation: "delete", key: key)
            throw error
        }
    }

    private func logKeychainError(_ error: Error, operation: String, key: SessionKey) {
        print("PatientSessionStore could not \(operation) \(key.rawValue): \(error.localizedDescription)")
    }
}
