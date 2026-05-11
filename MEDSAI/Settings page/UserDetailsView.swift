import SwiftUI

// MARK: - Routine Settings Screen

struct RoutineSettingsView: View {
    @EnvironmentObject var settings: AppSettings

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

            Section("Meals") {
                RoutineTimeRow(title: "Breakfast", comps: $settings.breakfast, defaultHour: 8)
                RoutineTimeRow(title: "Lunch",     comps: $settings.lunch,     defaultHour: 13)
                RoutineTimeRow(title: "Dinner",    comps: $settings.dinner,    defaultHour: 19)
            }

            Section(
                footer: Text("Changes are saved automatically. Medication reminders are refreshed whenever these times change.")
            ) {
                EmptyView()
            }
        }
        .navigationTitle("Daily Routine")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.orange)
        .onAppear {
            Task { await settings.loadRoutineFromSupabase() }
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
