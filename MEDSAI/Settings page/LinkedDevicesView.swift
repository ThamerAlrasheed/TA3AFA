import SwiftUI

struct LinkedDevicesView: View {
    let patientId: String
    let patientName: String
    
    @State private var devices: [PatientDevice] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var deviceToRevoke: PatientDevice?
    @State private var isRevoking = false
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }

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
                    Text(SettingsL10n.text("No linked devices found for this patient.", "لا توجد أجهزة مرتبطة بهذا المريض."))
                        .foregroundColor(.secondary)
                        .italic()
                        .multilineTextAlignment(SettingsL10n.textAlignment)
                }
            } else {
                Section(header: Text(SettingsL10n.text("Connected Devices", "الأجهزة المتصلة"))) {
                    ForEach(devices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
        .navigationTitle(SettingsL10n.text("\(patientName)'s Devices", "أجهزة \(patientName)"))
        .task {
            await loadDevices()
        }
        .alert(SettingsL10n.text("Revoke Device?", "إلغاء ربط الجهاز؟"), isPresented: Binding(
            get: { deviceToRevoke != nil },
            set: { if !$0 { deviceToRevoke = nil } }
        )) {
            Button(SettingsL10n.text("Revoke", "إلغاء الربط"), role: .destructive) {
                if let d = deviceToRevoke {
                    Task { await revoke(d) }
                }
            }
            Button(SettingsL10n.text("Cancel", "إلغاء"), role: .cancel) {}
        } message: {
            if let d = deviceToRevoke {
                Text(SettingsL10n.text(
                    "The device '\(d.device_name ?? "Unknown")' will no longer access this patient profile.",
                    "لن يتمكن الجهاز '\(d.device_name ?? "غير معروف")' من الوصول إلى ملف هذا المريض."
                ))
            }
        }
        .environment(\.layoutDirection, SettingsL10n.layoutDirection)
        .refreshable {
            await loadDevices()
        }
    }

    private func deviceRow(_ device: PatientDevice) -> some View {
        HStack(alignment: .center) {
            if isArabic {
                revokeButton(for: device)
                Spacer()
                deviceText(device)
            } else {
                deviceText(device)
                Spacer()
                revokeButton(for: device)
            }
        }
        .padding(.vertical, 4)
    }

    private func deviceText(_ device: PatientDevice) -> some View {
        VStack(alignment: isArabic ? .trailing : .leading, spacing: 4) {
            HStack {
                if isArabic, device.platform == "ios" {
                    Image(systemName: "applelogo").font(.caption)
                }
                Text(device.device_name ?? SettingsL10n.text("Unknown Device", "جهاز غير معروف"))
                    .bold()
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                if !isArabic, device.platform == "ios" {
                    Image(systemName: "applelogo").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)

            Group {
                if let appVer = device.app_version {
                    Text(SettingsL10n.text("App version: \(appVer)", "إصدار التطبيق: \(appVer)")).font(.caption2)
                }
                if let lastSeen = device.last_seen_at {
                    Text(SettingsL10n.text("Last seen: \(formatDate(lastSeen))", "آخر ظهور: \(formatDate(lastSeen))")).font(.caption2)
                }
                Text(SettingsL10n.text("Linked on: \(formatDate(device.created_at))", "تم الربط في: \(formatDate(device.created_at))"))
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
            .multilineTextAlignment(isArabic ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
    }

    private func revokeButton(for device: PatientDevice) -> some View {
        Button(SettingsL10n.text("Revoke", "إلغاء الربط")) {
            deviceToRevoke = device
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .controlSize(.small)
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
                self.errorMessage = SettingsL10n.text("Failed to load devices: \(error.localizedDescription)", "تعذر تحميل الأجهزة: \(error.localizedDescription)")
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
                self.errorMessage = SettingsL10n.text("Failed to revoke: \(error.localizedDescription)", "تعذر إلغاء الربط: \(error.localizedDescription)")
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
