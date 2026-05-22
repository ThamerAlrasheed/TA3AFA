import SwiftUI

/// Create or edit an appointment:
/// - Title (input)
/// - Type (menu with emoji)
/// - Date & Time
/// - Location
/// - Notes (optional)
struct AddAppointmentView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var repo: AppointmentsRepo
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }

    /// If non-nil, we are editing this appointment.
    let existing: Appointment?

    @State private var title: String
    @State private var type: AppointmentType
    @State private var date: Date
    @State private var location: String
    @State private var notes: String
    @State private var saveErrorMessage: String?

    init(repo: AppointmentsRepo, defaultDate: Date, existing: Appointment? = nil) {
        self.repo = repo
        self.existing = existing

        if let appt = existing {
            _title = State(initialValue: appt.title)
            _type = State(initialValue: appt.type)
            _date = State(initialValue: appt.date)
            _location = State(initialValue: appt.location ?? "")
            _notes = State(initialValue: appt.notes ?? "")
        } else {
            // default time at 10:00 on the picked day
            let cal = Calendar.current
            let defaultDT = cal.date(bySettingHour: 10, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            _title = State(initialValue: "")
            _type = State(initialValue: .doctor)
            _date = State(initialValue: defaultDT)
            _location = State(initialValue: "")
            _notes = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Title + Type side by side
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        TextField("Appointment title", text: $title)
                            .textInputAutocapitalization(.words)

                        Menu {
                            Picker("Type", selection: $type) {
                                ForEach(AppointmentType.allCases) { t in
                                    Text(t.label).tag(t)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(type.label)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .imageScale(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.istsehGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .menuIndicator(.hidden)
                    }

                    // Date & time
                    DatePicker("Date & time", selection: $date, displayedComponents: [.date, .hourAndMinute])

                    // Location
                    TextField("Location (optional)", text: $location)
                        .textInputAutocapitalization(.words)

                    // Notes
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                } header: {
                    Text("Details")
                }
                .listRowBackground(Color.istsehCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New Appointment" : "Edit Appointment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmed.isEmpty)
                }
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .alert("Unable to Save Appointment", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private func save() {
        if let appt = existing {
            repo.update(
                id: appt.id,
                title: title.trimmed,
                type: type,
                date: date,
                location: location.trimmed.nilIfEmpty,
                notes: notes.trimmed.nilIfEmpty
            ) { err in
                if let err {
                    saveErrorMessage = userFacingSaveError(from: err)
                } else {
                    dismiss()
                }
            }
        } else {
            repo.add(
                title: title.trimmed,
                type: type,
                date: date,
                location: location.trimmed.nilIfEmpty,
                notes: notes.trimmed.nilIfEmpty
            ) { err in
                if let err {
                    saveErrorMessage = userFacingSaveError(from: err)
                } else {
                    dismiss()
                }
            }
        }
    }

    private func userFacingSaveError(from error: Error) -> String {
        let message = error.localizedDescription
        if message.contains("42501") || message.localizedCaseInsensitiveContains("row-level security") {
            if SupabaseManager.shared.activePatientID == nil && !SupabaseManager.shared.isPatientMode {
                return "Unable to save appointment. Please try again."
            }
            return "You do not have permission to manage appointments for this profile."
        }
        return message.isEmpty ? "Please try again." : message
    }
}

// MARK: - Tiny helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
