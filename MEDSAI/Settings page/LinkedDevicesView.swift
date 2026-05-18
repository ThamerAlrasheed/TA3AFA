import SwiftUI

struct LinkedDevicesView: View {
    let patientId: String
    let patientName: String
    
    @State private var devices: [PatientDevice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var deviceToRevoke: PatientDevice?
    @State private var isRevoking = false

    var body: some View {
        List {
            if isLoading && devices.isEmpty {
                Section {
                    BrandedLoadingView(
                        message: LoadingMessage.custom("Loading devices…", "جاري تحميل الأجهزة…").text,
                        style: .inline
                    )
                }
            } else if let error = errorMessage {
                Section {
                    Text(error).foregroundColor(.red)
                }
            } else if devices.isEmpty {
                Section {
                    Text("No linked devices found for this patient.")
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                Section(header: Text("Connected Devices")) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
        .navigationTitle("\(patientName)'s Devices")
        .task {
            await loadDevices()
        }
        .alert("Revoke Device?", isPresented: Binding(
            get: { deviceToRevoke != nil },
            set: { if !$0 { deviceToRevoke = nil } }
        )) {
            Button("Revoke", role: .destructive) {
                if let d = deviceToRevoke {
                    Task { await revoke(d) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let d = deviceToRevoke {
                Text("The device '\(d.device_name ?? "Unknown")' will no longer access this patient profile.")
            }
        }
        .refreshable {
            await loadDevices()
        }
    }

    private func deviceRow(_ device: PatientDevice) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.device_name ?? "Unknown Device")
                        .bold()
                    if device.platform == "ios" {
                        Image(systemName: "applelogo").font(.caption)
                    }
                }
                
                Group {
                    if let appVer = device.app_version {
                        Text("App version: \(appVer)").font(.caption2)
                    }
                    if let lastSeen = device.last_seen_at {
                        Text("Last seen: \(formatDate(lastSeen))").font(.caption2)
                    }
                    Text("Linked on: \(formatDate(device.created_at))")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Revoke") {
                deviceToRevoke = device
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func loadDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            let list = try await DrugInfo.listDevices(patientId: patientId)
            await MainActor.run {
                self.devices = list
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load devices: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    private func revoke(_ device: PatientDevice) async {
        isRevoking = true
        do {
            try await DrugInfo.revokeDevice(patientId: patientId, deviceId: device.id)
            await loadDevices() // Refresh
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to revoke: \(error.localizedDescription)"
            }
        }
        isRevoking = false
    }

    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
