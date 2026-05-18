import SwiftUI

// MARK: - Routine Settings Screen

struct RoutineSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }

    var body: some View {
        Form {
            if let patientName = settings.activePatientName {
                Section {
                    Label("Managing \(patientName)'s routine", systemImage: "person.2.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            Section("Sleep") {
                RoutineTimeRow(title: "Wake time", comps: $settings.wakeup,   defaultHour: 7)
                RoutineTimeRow(title: "Bedtime",   comps: $settings.bedtime,  defaultHour: 23)
            }
            .listRowBackground(Color.istsehCard)

            Section("Meals") {
                RoutineTimeRow(title: "Breakfast", comps: $settings.breakfast, defaultHour: 8)
                RoutineTimeRow(title: "Lunch",     comps: $settings.lunch,     defaultHour: 13)
                RoutineTimeRow(title: "Dinner",    comps: $settings.dinner,    defaultHour: 19)
            }
            .listRowBackground(Color.istsehCard)

            Section(
                footer: Text("Changes save automatically. Medication reminders are refreshed when these times change.")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            ) {
                EmptyView()
            }
            .listRowBackground(Color.istsehCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.istsehPageBackground.ignoresSafeArea())
        .navigationTitle("Daily Routine")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .onAppear {
            Task { await settings.loadRoutineFromSupabase() }
        }
        .overlay(alignment: .bottom) {
            RoutineSaveToast(status: settings.routineSaveStatus)
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Save status toast

private struct RoutineSaveToast: View {
    let status: AppSettings.RoutineSaveStatus

    private var isVisible: Bool { status != .idle }

    private var icon: String {
        switch status {
        case .saving: return "arrow.triangle.2.circlepath"
        case .saved:  return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle:   return ""
        }
    }

    private var label: String {
        switch status {
        case .saving: return "Saving…"
        case .saved:  return "Saved"
        case .failed: return "Save failed"
        case .idle:   return ""
        }
    }

    private var tint: Color {
        switch status {
        case .saving: return .orange
        case .saved:  return Color.istsehGreen
        case .failed: return .red
        case .idle:   return .clear
        }
    }

    var body: some View {
        if isVisible {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(tint, in: Capsule())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
        }
    }
}

// MARK: - Routine Time Row

private struct RoutineTimeRow: View {
    let title: String
    @Binding var comps: DateComponents
    let defaultHour: Int

    var body: some View {
        DatePicker(
            title,
            selection: Binding<Date>(
                get: {
                    Calendar.current.date(from: comps)
                        ?? Calendar.current.date(from: DateComponents(hour: defaultHour, minute: 0))
                        ?? Date()
                },
                set: { newDate in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                    comps.hour   = parts.hour
                    comps.minute = parts.minute
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}
