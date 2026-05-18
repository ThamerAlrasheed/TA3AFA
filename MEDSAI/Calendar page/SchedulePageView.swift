import SwiftUI

/// Calendar page – calendar picker at the top, then Appointments, then Doses.
struct SchedulePageView: View {
    @EnvironmentObject var settings: AppSettings

    @StateObject private var repo = UserMedsRepo()
    @StateObject private var appts = AppointmentsRepo()

    @State private var selectedDate: Date = Date()
    @State private var dayDoses: [(Date, LocalMed)] = []

    @State private var showAddAppointment = false
    @State private var editingAppointment: Appointment? = nil

    private var canEditAppointments: Bool {
        if settings.role == .patient {
            return repo.canManageCalendar
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Calendar picker — inline at top
                    CalendarView(selection: $selectedDate, initialMode: .monthly)
                        .padding(.bottom, 4)

                    Divider().padding(.horizontal)

                    // Appointments
                    appointmentsBlock

                    // Doses
                    dosesBlock
                }
                .padding(.bottom, 100)
            }
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle("Calendar")
            .refreshable {
                repo.start()
                appts.start()
            }
            .toolbar {
                if settings.role == .caregiver {
                    ToolbarItem(placement: .topBarLeading) {
                        CareProfileMenu {
                            repo.start()
                            appts.start()
                            recomputeDoses()
                        }
                        .environmentObject(settings)
                    }
                }
            }
            .onAppear {
                repo.start()
                appts.start()
                recomputeDoses()
            }
            .onChange(of: selectedDate) { _, _ in recomputeDoses() }
            .onChange(of: repo.meds) { _, _ in recomputeDoses() }
            .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
            .onChange(of: settings.lunch)     { _, _ in recomputeDoses() }
            .onChange(of: settings.dinner)    { _, _ in recomputeDoses() }
            .onChange(of: settings.bedtime)   { _, _ in recomputeDoses() }
            .onChange(of: settings.wakeup)    { _, _ in recomputeDoses() }
            .onChange(of: settings.activePatientID) { _, _ in
                repo.start()
                appts.start()
                recomputeDoses()
            }
            .sheet(isPresented: $showAddAppointment) {
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: nil)
            }
            .sheet(item: $editingAppointment) { appt in
                AddAppointmentView(repo: appts, defaultDate: selectedDate, existing: appt)
            }
        }
    }

    // MARK: - Appointments block (above doses)
    private var appointmentsBlock: some View {
        SectionCard {
            SectionHeader(title: sectionTitle("Appointments"))

            let items = appts.appointments(on: selectedDate)

            if appts.isLoading {
                rowPadding(
                    BrandedLoadingView(message: LoadingMessage.appointments.text, style: .inline)
                )
            } else if let err = appts.errorMessage {
                rowPadding(
                    ContentUnavailableView(LoadingMessage.scheduleError.text,
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                )
            } else if items.isEmpty {
                rowPadding(
                    VStack(alignment: .center, spacing: 10) {
                        ISTSEHInlineEmptyState(
                            systemImage: "calendar.badge.clock",
                            title: LoadingMessage.noAppointmentsOnDay.text
                        )

                        if canEditAppointments {
                            HStack {
                                Spacer()
                                CenteredPillButton(title: "Add appointment") {
                                    showAddAppointment = true
                                }
                                .frame(maxWidth: 260)
                                Spacer()
                            }
                        }
                    }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { appt in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appt.titleWithEmoji)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let loc = appt.location, !loc.isEmpty {
                                        Text(loc)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let notes = appt.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                Spacer()

                                Text(timeOnly(appt.date))
                                    .font(.headline)
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)

                                if canEditAppointments {
                                    Menu {
                                        Button { editingAppointment = appt } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            Task { await appts.delete(appt) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                            .padding(.leading, 4)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)
                    }

                    if canEditAppointments {
                        // Centered "Add appointment" pill under list
                        HStack {
                            Spacer()
                            CenteredPillButton(title: "Add appointment") {
                                showAddAppointment = true
                            }
                            .frame(maxWidth: 260)
                            Spacer()
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    // MARK: - Doses block (read-only, with empty state)
    private var dosesBlock: some View {
        SectionCard {
            SectionHeader(title: sectionTitle("Doses"))

            if repo.isLoading {
                rowPadding(
                    BrandedLoadingView(message: LoadingMessage.medications.text, style: .inline)
                )
            } else if let err = repo.errorMessage {
                rowPadding(
                    ContentUnavailableView(LoadingMessage.scheduleError.text,
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                )
            } else if dayDoses.isEmpty {
                rowPadding(
                    ISTSEHInlineEmptyState(
                        systemImage: "calendar.badge.exclamationmark",
                        title: LoadingMessage.noDosesOnDay.text
                    )
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(dayDoses.indices, id: \.self) { i in
                        let pair = dayDoses[i]
                        let time = pair.0
                        let med  = pair.1

                        HStack(spacing: 12) {
                            MedicationVisualView(
                                form: med.medicationForm,
                                shapeID: med.visualShape,
                                medicationColorID: med.visualColor,
                                backgroundColorID: med.visualBackgroundColor,
                                size: 40
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.doseActionText(isArabic: isArabic)).font(.headline)
                                Text(medicationSubtitle(med))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(time.formatted(date: .omitted, time: .shortened))
                                .font(.headline)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Build Doses for selected day (READ-ONLY)
    private func recomputeDoses() {
        guard repo.isSignedIn else {
            dayDoses = []
            return
        }

        let active = repo.meds.filter { med in
            guard !med.isArchived else { return false }
            return med.isScheduled(on: selectedDate)
        }
        if active.isEmpty {
            dayDoses = []
            return
        }

        let display: [(Date, LocalMed)] = active.flatMap { med in
            doseDates(for: med, on: selectedDate).map { ($0, med) }
        }
        dayDoses = display.sorted { $0.0 < $1.0 }
    }

    private func doseDates(for med: LocalMed, on date: Date) -> [Date] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: date)
        let explicitTimes = med.dosageTimes.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        }
        if !explicitTimes.isEmpty { return explicitTimes }

        let adapted = Medication(
            id: med.id,
            name: med.name,
            dosage: med.dosage,
            frequencyPerDay: med.frequencyPerDay,
            startDate: med.startDate,
            endDate: med.endDate,
            foodRule: med.foodRule,
            notes: med.notes,
            ingredients: med.ingredients,
            minIntervalHours: med.minIntervalHours,
            rxcui: med.rxcui,
            dosageTimes: nil,
            asNeeded: med.asNeeded,
            isManualSchedule: med.isManualSchedule
        )
        return Scheduler.preferredTimes(for: adapted, on: base, settings: settings)
    }

    // MARK: - Formatting helpers
    private func sectionTitle(_ base: String) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return "\(base) – \(df.string(from: selectedDate))"
    }

    private func foodRuleLabel(_ rule: FoodRule) -> String {
        switch rule {
        case .beforeFood: return "Before food"
        case .afterFood:  return "After food"
        case .withFood:   return "With food"
        case .avoidWithFood: return "Avoid with food"
        case .notSure: return "Not sure"
        case .none:       return "No food rule"
        }
    }

    private func medicationSubtitle(_ med: LocalMed) -> String {
        let food = MedicationFormRules.shouldShowFoodTiming(
            formID: med.medicationForm,
            foodRule: med.foodRule,
            sourceBacked: med.foodRuleSource == "source"
        ) ? med.foodRuleLabel(isArabic: isArabic) : nil
        return [med.scheduleSummary(isArabic: isArabic), food]
            .compactMap { $0 }
            .joined(separator: " • ")
    }

    private var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }

    private func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func rowPadding<V: View>(_ v: V) -> some View {
        v.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Section chrome (List-like look without List)
private struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(Color.istsehCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

// MARK: - Button
private struct CenteredPillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .frame(minWidth: 160, maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .background(Color.istsehGreen)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
