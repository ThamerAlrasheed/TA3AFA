import SwiftUI

struct PatientSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 15) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(settings.firstName) \(settings.lastName)")
                                .font(.headline)
                            Text("Account managed by caregiver")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Connected Caregiver")) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.teal)
                        Text("Your Caregiver")
                        Spacer()
                        Text("Active")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Management")) {
                    if let pid = settings.activePatientID {
                        NavigationLink(destination: LinkedDevicesView(patientId: pid, patientName: settings.activePatientName ?? "Patient")) {
                            HStack {
                                Image(systemName: "iphone.badge.checkmark")
                                    .foregroundStyle(.blue)
                                Text("Linked Devices")
                            }
                        }
                    }
                    
                    NavigationLink(destination: MedicalProfileView(patientId: settings.activePatientID, patientName: settings.activeCareDisplayName)) {
                        HStack {
                            Image(systemName: "medical.sheet.fill")
                                .foregroundStyle(.red)
                            Text("Medical Profile")
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Disconnect from Caregiver")
                                .bold()
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Doing this will log you out and stop syncing with your caregiver.")
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func disconnect() {
        // Clear session
        PatientSessionStore.shared.clearAllSessionValuesBestEffort()
        
        // Reset app state
        settings.role = .regular
        settings.onboardingCompleted = false
        settings.didChooseEntry = false
        
        // Any other cleanup
        Task {
            do {
                try await SupabaseManager.shared.client.auth.signOut()
            } catch {
                print("⚠️ Sign out failed:", error.localizedDescription)
            }
        }
    }
}
