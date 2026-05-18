import SwiftUI
import UserNotifications

/// "Today" page:
/// - Shows today's Appointments (tap to see details) with a checkmark.
/// - Shows today's Doses from midnight → **tomorrow’s wake time** (includes sleeping window).
struct TodayScheduleView: View {
    @EnvironmentObject var settings: AppSettings

    // Repos (match your project types)
    @StateObject private var medsRepo = UserMedsRepo()
    @StateObject private var apptsRepo = AppointmentsRepo()

    // Today anchor (recomputed on appear)
    @State private var today: Date = Date()

    // Derived
    @State private var todaysDoses: [(Date, LocalMed)] = []

    // Completion state (persistent via UserDefaults so actions from notifications are reflected)
    @State private var completedAppointments: Set<String> = CompletionStore.completedAppointments()
    @State private var completedDoseKeys: Set<String> = CompletionStore.completedDoses()

    // Sheet state for viewing appointment details
    @State private var viewingAppointment: Appointment? = nil

    var body: some View {
        NavigationStack {
            List {
                // MARK: Appointments section
                Section(header: Text(sectionTitle())) {
                    appointmentsSection
                }
                .listRowBackground(Color.istsehCard)

                // MARK: Doses section
                Section {
                    dosesSection
                }
                .listRowBackground(Color.istsehCard)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle("Today")
            .refreshable {
                medsRepo.start()
                apptsRepo.start()
            }
            .toolbar {
                if settings.role == .caregiver {
                    ToolbarItem(placement: .topBarLeading) {
                        CareProfileMenu {
                            medsRepo.start()
                            apptsRepo.start()
                            recomputeDoses()
                        }
                        .environmentObject(settings)
                    }
                }
            }
            .onAppear {
                today = Calendar.current.startOfDay(for: Date())
                medsRepo.start()
                apptsRepo.start()
                recomputeDoses()

                // Refresh completion state (in case a background action toggled it)
                completedAppointments = CompletionStore.completedAppointments()
                completedDoseKeys = CompletionStore.completedDoses()

                Task {
                    await NotificationsManager.shared.requestAuthorization()
                }
            }
            .onChange(of: medsRepo.meds) { _, _ in
                recomputeDoses()
            }
            .onChange(of: settings.activePatientID) { _, _ in
                medsRepo.start()
                apptsRepo.start()
                recomputeDoses()
            }
            .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
            .onChange(of: settings.lunch)     { _, _ in recomputeDoses() }
            .onChange(of: settings.dinner)    { _, _ in recomputeDoses() }
            .onChange(of: settings.bedtime)   { _, _ in recomputeDoses() }
            .onChange(of: settings.wakeup)    { _, _ in recomputeDoses() }

            .sheet(item: $viewingAppointment) { appt in
                AppointmentDetailSheet(appointment: appt)
                    .presentationDetents([.medium, .large])
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    // MARK: - Appointments UI

    @ViewBuilder
    private var appointmentsSection: some View {
        if apptsRepo.isLoading {
            BrandedLoadingView(message: LoadingMessage.appointments.text, style: .inline)
        } else if let err = apptsRepo.errorMessage {
            ContentUnavailableView(LoadingMessage.scheduleError.text,
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(err))
        } else {
            let items = apptsRepo.appointments(on: today).sorted(by: { $0.date < $1.date })
            if items.isEmpty {
                ISTSEHInlineEmptyState(
                    systemImage: "calendar.badge.clock",
                    title: LoadingMessage.noAppointmentsToday.text
                )
            } else {
                ForEach(items) { appt in
                    TodayRow(
                        isDone: completedAppointments.contains(appt.id),
                        leadingIcon: "",
                        title: appt.titleWithEmoji,
                        subtitle: apptSubtitle(appt),
                        timeText: timeOnly(appt.date),
                        toggle: { toggleAppointment(appt.id) },
                        onTap: { viewingAppointment = appt }
                    )
                }
            }
        }
    }

    // MARK: - Doses UI

    @ViewBuilder
    private var dosesSection: some View {
        if medsRepo.isLoading {
            BrandedLoadingView(message: LoadingMessage.medications.text, style: .inline)
        } else if let err = medsRepo.errorMessage {
            ContentUnavailableView(LoadingMessage.scheduleError.text,
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(err))
        } else if todaysDoses.isEmpty {
            ISTSEHInlineEmptyState(
                systemImage: "pills.fill",
                title: LoadingMessage.noMedicationsDueToday.text
            )
        } else {
            ForEach(todaysDoses.indices, id: \.self) { i in
                let (time, med) = todaysDoses[i]
                let key = doseKey(time: time, medID: med.id)

                TodayRow(
                    isDone: completedDoseKeys.contains(key),
                    leadingIcon: "💊",
                    medication: med,
                    title: med.doseActionText(isArabic: isArabic),
                    subtitle: medicationSubtitle(med),
                    timeText: time.formatted(date: .omitted, time: .shortened),
                    toggle: {
                        toggleDose(key, medID: med.id, time: time)
                        NotificationsManager.shared.cancel(ids: ["DOSE_FU_\(key)"])
                    },
                    onTap: {
                        toggleDose(key, medID: med.id, time: time)
                        NotificationsManager.shared.cancel(ids: ["DOSE_FU_\(key)"])
                    }
                )
                .contextMenu {
                    if !completedDoseKeys.contains(key) {
                        Button {
                            markAsSkipped(key, medID: med.id, time: time)
                        } label: {
                            Label("Skip Dose", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Build Doses for today (midnight → tomorrow's wake)

    private func recomputeDoses() {
        guard medsRepo.isSignedIn else {
            todaysDoses = []
            return
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: today)
        let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart)!

        // Wider "today" window upper bound = **tomorrow's wake**
        let nextWake = cal.date(
            bySettingHour: settings.wakeup.hour ?? 7,
            minute: settings.wakeup.minute ?? 0,
            second: 0,
            of: dayEnd
        ) ?? dayEnd.addingTimeInterval(7 * 3600)

        // Day-overlap: treat meds starting later today as active today
        let active = medsRepo.meds.filter { med in
            guard !med.isArchived else { return false }
            return med.startDate < dayEnd && med.endDate >= dayStart && med.isScheduled(on: dayStart, calendar: cal)
        }
        guard !active.isEmpty else {
            todaysDoses = []
            return
        }

        todaysDoses = active
            .flatMap { med in doseDates(for: med, on: dayStart).map { ($0, med) } }
            .filter { (t, _) in t >= dayStart && t < nextWake }
            .sorted { $0.0 < $1.0 }
        #if DEBUG
        print("decoded visual fields on Today dose generation: \(todaysDoses.map { "\($0.1.name) visual=(\($0.1.visualShape ?? "nil"),\($0.1.visualColor ?? "nil"),\($0.1.visualBackgroundColor ?? "nil")) fallback=\($0.1.visualShape == nil || $0.1.visualColor == nil || $0.1.visualBackgroundColor == nil) refill=(enabled:\($0.1.refillReminderEnabled),date:\($0.1.refillReminderDate != nil))" })")
        #endif
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

    // MARK: - Completion toggles

    private func toggleAppointment(_ id: String) {
        if completedAppointments.contains(id) {
            completedAppointments.remove(id)
        } else {
            completedAppointments.insert(id)
        }
        CompletionStore.setCompletedAppointments(completedAppointments)
    }

    private func toggleDose(_ key: String, medID: String, time: Date) {
        let isDone: Bool
        if completedDoseKeys.contains(key) {
            completedDoseKeys.remove(key)
            isDone = false
        } else {
            completedDoseKeys.insert(key)
            isDone = true
        }
        CompletionStore.setCompletedDoses(completedDoseKeys)
        
        // Sync to Supabase
        if isDone {
            Task {
                do {
                    try await SupabaseManager.shared.recordDoseEvent(
                        medId: medID,
                        scheduledAt: time,
                        status: .taken
                    )
                } catch {
                    print("⚠️ Failed to sync dose event:", error)
                }
            }
        }
    }

    private func markAsSkipped(_ key: String, medID: String, time: Date) {
        completedDoseKeys.insert(key)
        CompletionStore.setCompletedDoses(completedDoseKeys)
        
        Task {
            do {
                try await SupabaseManager.shared.recordDoseEvent(
                    medId: medID,
                    scheduledAt: time,
                    status: .skipped
                )
            } catch {
                print("⚠️ Failed to sync skipped event:", error)
            }
        }
    }

    // MARK: - Helpers

    private func apptSubtitle(_ appt: Appointment) -> String {
        var parts: [String] = []
        if let loc = appt.location, !loc.isEmpty { parts.append(loc) }
        if let notes = appt.notes, !notes.isEmpty { parts.append(notes) }
        return parts.isEmpty ? "" : parts.joined(separator: " • ")
    }

    private func sectionTitle() -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return df.string(from: today)
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

    private func timeOnly(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Stable unique key for a dose row (per med per time)
    private func doseKey(time: Date, medID: String) -> String {
        NotificationsManager.medicationDoseKey(medID: medID, scheduledAt: time)
    }

    private var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }
}

// MARK: - Reusable "Today" row with a tick and tap
private struct TodayRow: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let isDone: Bool
    let leadingIcon: String
    var medication: LocalMed? = nil
    let title: String
    let subtitle: String
    let timeText: String
    let toggle: () -> Void
    let onTap: () -> Void

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggle) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? .green : .secondary)
                    .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")
            }
            .buttonStyle(.plain)

            if let medication {
                MedicationVisualView(
                    form: medication.medicationForm,
                    shapeID: medication.visualShape,
                    medicationColorID: medication.visualColor,
                    backgroundColorID: medication.visualBackgroundColor,
                    size: 38
                )
            } else if !leadingIcon.isEmpty {
                Text(leadingIcon)
            }

            VStack(alignment: isRTL ? .trailing : .leading, spacing: 2) {
                Text(title).font(.headline)
                    .strikethrough(isDone, color: .secondary)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .multilineTextAlignment(isRTL ? .trailing : .leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                }
            }

            Spacer()

            Text(timeText)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(isDone ? .secondary : .primary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Appointment detail sheet
private struct AppointmentDetailSheet: View {
    let appointment: Appointment

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(appointment.titleWithEmoji)
                            .font(.headline)
                        Spacer()
                    }
                    HStack {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text(timeAndDate(appointment.date))
                    }
                }
                if let loc = appointment.location, !loc.isEmpty {
                    Section("Location") {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                            Text(loc)
                        }
                    }
                }
                if let notes = appointment.notes, !notes.isEmpty {
                    Section("Notes") { Text(notes) }
                }
            }
            .navigationTitle("Appointment")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func timeAndDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}
