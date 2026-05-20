import SwiftUI

struct PatientSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 15) {
                        if !isArabic {
                            profileIcon
                        }
                        
                        VStack(alignment: isArabic ? .trailing : .leading, spacing: 4) {
                            Text("\(settings.firstName) \(settings.lastName)")
                                .font(.headline)
                            Text(SettingsL10n.text("Account managed by caregiver", "الحساب مُدار بواسطة مقدم الرعاية"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: SettingsL10n.frameAlignment)

                        if isArabic {
                            profileIcon
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text(SettingsL10n.text("Connected Caregiver", "مقدم الرعاية المرتبط"))) {
                    SettingsValueRow(
                        title: SettingsL10n.text("Your Caregiver", "مقدم الرعاية"),
                        value: SettingsL10n.text("Active", "نشط")
                    )
                }

                Section(header: Text(SettingsL10n.text("Management", "الإدارة"))) {
                    if let pid = settings.activePatientID {
                        SettingsLinkRow(
                            icon: "iphone.badge.checkmark",
                            text: SettingsL10n.text("Linked Devices", "الأجهزة المرتبطة"),
                            showsDivider: true
                        ) {
                            LinkedDevicesView(patientId: pid, patientName: settings.activePatientName ?? "Patient")
                        }
                    }
                    
                    SettingsLinkRow(
                        icon: "medical.sheet.fill",
                        text: SettingsL10n.text("Medical Profile", "الملف الطبي"),
                        iconColor: .red
                    ) {
                        MedicalProfileView(patientId: settings.activePatientID, patientName: settings.activeCareDisplayName)
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        HStack {
                            Spacer()
                            Text(SettingsL10n.text("Disconnect from Caregiver", "قطع الاتصال بمقدم الرعاية"))
                                .bold()
                            Spacer()
                        }
                    }
                } footer: {
                    Text(SettingsL10n.text(
                        "Doing this will log you out and stop syncing with your caregiver.",
                        "سيؤدي ذلك إلى تسجيل خروجك وإيقاف المزامنة مع مقدم الرعاية."
                    ))
                    .multilineTextAlignment(SettingsL10n.textAlignment)
                }
            }
            .navigationTitle(SettingsL10n.text("Settings", "الإعدادات"))
        }
        .environment(\.layoutDirection, SettingsL10n.layoutDirection)
    }

    private var profileIcon: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .frame(width: 60, height: 60)
            .foregroundStyle(Color.istsehGreen)
    }
    
    private func disconnect() {
        Task {
            await settings.signOutCompletely()
        }
    }
}
