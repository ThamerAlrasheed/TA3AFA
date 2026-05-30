import SwiftUI
struct CareCodeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    
    @State private var code: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let codeLength = 6

    private var cleanCode: String {
        Self.normalizedCode(code)
    }
    
    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.green)
                
                Text("Enter Family Code")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Ask your caregiver for the 6-digit family code.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 60)
            
            // Invisible TextField drives keyboard input.
            // Visible CharacterBox row renders the digits.
            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<Self.codeLength, id: \.self) { index in
                        CharacterBox(char: character(at: index))
                    }
                }

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .focused($isTextFieldFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: code) { _, newValue in
                        let normalized = Self.normalizedCode(newValue)
                        // Keep only digits, max 6 chars.
                        if normalized != newValue {
                            code = normalized
                        }
                        // Clear any stale error as soon as the user edits.
                        if errorMessage != nil {
                            errorMessage = nil
                        }
                        #if DEBUG
                        print("DEBUG CareCodeEntryView: code changed, digitCount=\(normalized.count)")
                        #endif
                    }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFieldFocused = true
            }
            
            // Only show error when it is non-nil AND code is not being actively typed
            // (prevents stale errors from a previous session appearing with empty boxes).
            if let error = errorMessage, !error.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
            
            Spacer()
            
            Button {
                submitCode()
            } label: {
                HStack {
                    if isLoading {
                        ISTSEHLoadingView(message: "", style: .compact)
                            .frame(width: 24, height: 24)
                            .padding(.trailing, 8)
                    }
                    Text("Connect")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(cleanCode.count != Self.codeLength || isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Always reset state when view appears so a previous
            // failed attempt's error is never shown with empty boxes.
            code = ""
            errorMessage = nil
            isLoading = false
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
        }
    }
    
    @FocusState private var isTextFieldFocused: Bool
    
    private func character(at index: Int) -> String {
        let digits = cleanCode
        guard index < digits.count else { return "" }
        let charIndex = digits.index(digits.startIndex, offsetBy: index)
        return String(digits[charIndex])
    }
    
    // Called ONLY by the Connect button tap.
    private func submitCode() {
        let submittedCode = cleanCode

        // Silent guard — button is already disabled when count < 6.
        guard submittedCode.count == Self.codeLength else {
            #if DEBUG
            print("DEBUG CareCodeEntryView: blocked redeem — code count != 6 (actual=\(submittedCode.count))")
            #endif
            return
        }

        #if DEBUG
        print("DEBUG CareCodeEntryView: [1] submit started, digitCount=\(submittedCode.count)")
        #endif

        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Clear any stale caregiver context before redeeming.
                await MainActor.run {
                    settings.resetUserScopedState()
                    settings.stopActingAsPatient()
                }
                #if DEBUG
                print("DEBUG CareCodeEntryView: [2] context cleared, calling redeemCareCode")
                #endif

                let result = try await SupabaseManager.shared.redeemCareCode(submittedCode)

                #if DEBUG
                print("DEBUG CareCodeEntryView: [3] redeemCareCode returned, saving session")
                #endif

                try PatientSessionStore.shared.savePatientSession(
                    patientID: result.patientID,
                    deviceToken: result.deviceToken
                )

                #if DEBUG
                print("DEBUG CareCodeEntryView: [4] session saved to keychain")
                #endif

                NotificationCenter.default.post(
                    name: NSNotification.Name("SupabaseContextChanged"), object: nil
                )

                await MainActor.run {
                    #if DEBUG
                    print("DEBUG CareCodeEntryView: [5] setting app state and dismissing")
                    #endif
                    isLoading = false
                    settings.role = .patient
                    settings.onboardingCompleted = true
                    settings.didChooseEntry = true
                    dismiss()
                }
            } catch {
                #if DEBUG
                print("DEBUG CareCodeEntryView: [ERROR] \(error)")
                #endif
                await MainActor.run {
                    isLoading = false
                    let msg = error.localizedDescription.lowercased()
                    if msg.contains("invalid") ||
                       msg.contains("expired") ||
                       msg.contains("used") ||
                       msg.contains("6-digit") {
                        errorMessage = "Invalid family code. Please check the code and try again."
                    } else if msg.contains("finish setup") || msg.contains("restart") {
                        errorMessage = "Code accepted, but the app could not finish setup. Please restart and try again."
                    } else {
                        errorMessage = "Could not connect right now. Please try again."
                    }
                    // Keep the entered code so the user can edit and retry.
                }
            }
        }
    }

    private static func normalizedCode(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(codeLength))
    }

}

private struct CharacterBox: View {
    let char: String
    
    var body: some View {
        Text(char)
            .font(.system(size: 32, weight: .bold, design: .monospaced))
            .frame(width: 45, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(char.isEmpty ? Color.primary.opacity(0.1) : Color.green, lineWidth: 2)
            )
    }
}

#Preview {
    CareCodeEntryView()
        .environmentObject(AppSettings.shared)
}
