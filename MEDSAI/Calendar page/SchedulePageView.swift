import SwiftUI

/// Calendar page: date picker plus the shared daily board used by Today.
struct SchedulePageView: View {
    @EnvironmentObject var settings: AppSettings

    @StateObject private var repo = UserMedsRepo()
    @StateObject private var appts = AppointmentsRepo()

    @State private var selectedDate: Date = Date()
    @State private var dayDoses: [(Date, LocalMed)] = []
    @State private var completedAppointments: Set<String> = CompletionStore.completedAppointments()
    @State private var completedDoseKeys: Set<String> = CompletionStore.completedDoses()
    @State private var skippedDoseKeys: Set<String> = DailyDoseStatusStore.skippedDoses()

    @State private var showAddAppointment = false
    @State private var editingAppointment: Appointment? = nil
    @State private var viewingMedication: LocalMed? = nil

    private var canEditAppointments: Bool {
        if settings.role == .patient {
            return repo.canManageCalendar
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CalendarView(selection: $selectedDate, initialMode: .monthly)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Divider()

                content
            }
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle(isArabic ? "الجدول" : "Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                repo.start()
                appts.start()
                refreshCompletionState()
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

                if canEditAppointments {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddAppointment = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add appointment")
                    }
                }
            }
            .onAppear {
                repo.start()
                appts.start()
                recomputeDoses()
                refreshCompletionState()
            }
            .onChange(of: selectedDate) { _, _ in recomputeDoses() }
            .onChange(of: repo.meds) { _, _ in recomputeDoses() }
            .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
            .onChange(of: settings.lunch) { _, _ in recomputeDoses() }
            .onChange(of: settings.dinner) { _, _ in recomputeDoses() }
            .onChange(of: settings.bedtime) { _, _ in recomputeDoses() }
            .onChange(of: settings.wakeup) { _, _ in recomputeDoses() }
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
            .sheet(item: $viewingMedication) { med in
                NavigationStack {
                    MedDetailView(medName: med.name, catalogId: med.catalogId, med: med)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder
    private var content: some View {
        if (repo.isLoading || appts.isLoading) && !repo.hasLoadedOnce && repo.meds.isEmpty {
            ISTSEHLoadingView(
                message: LoadingMessage.custom("Loading schedule", "جاري تحميل الجدول").text,
                style: .fullScreen
            )
        } else if let errorMessage = repo.errorMessage ?? appts.errorMessage, repo.meds.isEmpty && appts.items.isEmpty {
            ContentUnavailableView(
                LoadingMessage.scheduleError.text,
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DailyBoardView(
                selectedDate: selectedDate,
                medicationGroups: selectedDayMedicationGroups,
                appointmentGroups: selectedDayAppointmentGroups,
                onToggleDose: toggleDose,
                onSkipDose: skipDose,
                onOpenMedication: openMedication,
                onToggleAppointment: toggleAppointment,
                onOpenAppointment: openAppointment
            )
        }
    }

    private var selectedDayMedicationGroups: [DailyMedicationGroup] {
        DailyBoardBuilder.buildMedicationGroups(
            medications: repo.meds,
            doseItems: dayDoses.map(doseDisplayItem),
            for: selectedDate
        )
    }

    private var selectedDayAppointmentGroups: [DailyAppointmentGroup] {
        DailyBoardBuilder.buildAppointmentGroups(
            appointments: appts.appointments(on: selectedDate),
            completedAppointmentIDs: completedAppointments,
            for: selectedDate
        )
    }

    private func doseDisplayItem(for pair: (Date, LocalMed)) -> DailyDoseDisplayItem {
        let key = doseKey(time: pair.0, medID: pair.1.id)
        return DailyDoseDisplayItem(
            id: key,
            medicationID: pair.1.id,
            scheduledAt: pair.0,
            displayTime: pair.0.formatted(date: .omitted, time: .shortened),
            status: doseStatus(for: key, scheduledAt: pair.0)
        )
    }

    private func doseStatus(for key: String, scheduledAt: Date) -> DoseDisplayStatus {
        if skippedDoseKeys.contains(key) { return .skipped }
        if completedDoseKeys.contains(key) { return .taken }
        if scheduledAt < Date() { return .missed }
        return .pending
    }

    private func recomputeDoses() {
        guard repo.isSignedIn else {
            dayDoses = []
            return
        }

        let active = repo.meds.filter { med in
            guard !med.isArchived else { return false }
            return med.isScheduled(on: selectedDate)
        }

        dayDoses = DoseTextFormatter.deduplicatedDosePairs(active.flatMap { med in
            doseDates(for: med, on: selectedDate).map { ($0, med) }
        })
    }

    private func doseDates(for med: LocalMed, on date: Date) -> [Date] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: date)
        let explicitTimes = med.dosageTimes.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)
        }
        if !explicitTimes.isEmpty { return DoseTextFormatter.deduplicatedDoseDates(explicitTimes, calendar: cal) }

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
        return DoseTextFormatter.deduplicatedDoseDates(
            Scheduler.preferredTimes(for: adapted, on: base, settings: settings),
            calendar: cal
        )
    }

    private func toggleAppointment(_ item: DailyAppointmentDisplayItem) {
        if completedAppointments.contains(item.appointmentID) {
            completedAppointments.remove(item.appointmentID)
        } else {
            completedAppointments.insert(item.appointmentID)
        }
        CompletionStore.setCompletedAppointments(completedAppointments)
    }

    private func toggleDose(_ item: DailyDoseDisplayItem) {
        let isDone: Bool
        if completedDoseKeys.contains(item.id), !skippedDoseKeys.contains(item.id) {
            completedDoseKeys.remove(item.id)
            isDone = false
        } else {
            completedDoseKeys.insert(item.id)
            skippedDoseKeys.remove(item.id)
            isDone = true
        }
        persistDoseState()
        NotificationsManager.shared.cancel(ids: ["DOSE_FU_\(item.id)"])

        if isDone {
            Task {
                do {
                    try await SupabaseManager.shared.recordDoseEvent(
                        medId: item.medicationID,
                        scheduledAt: item.scheduledAt,
                        status: .taken
                    )
                } catch {
                    print("⚠️ Failed to sync dose event:", error)
                }
            }
        }
    }

    private func skipDose(_ item: DailyDoseDisplayItem) {
        completedDoseKeys.insert(item.id)
        skippedDoseKeys.insert(item.id)
        persistDoseState()

        Task {
            do {
                try await SupabaseManager.shared.recordDoseEvent(
                    medId: item.medicationID,
                    scheduledAt: item.scheduledAt,
                    status: .skipped
                )
            } catch {
                print("⚠️ Failed to sync skipped event:", error)
            }
        }
    }

    private func openMedication(_ group: DailyMedicationGroup) {
        viewingMedication = repo.meds.first { $0.id == group.medicationID }
    }

    private func openAppointment(_ item: DailyAppointmentDisplayItem?) {
        guard canEditAppointments, let item else { return }
        editingAppointment = appts.items.first { $0.id == item.appointmentID }
    }

    private func refreshCompletionState() {
        completedAppointments = CompletionStore.completedAppointments()
        completedDoseKeys = CompletionStore.completedDoses()
        skippedDoseKeys = DailyDoseStatusStore.skippedDoses()
    }

    private func persistDoseState() {
        CompletionStore.setCompletedDoses(completedDoseKeys)
        DailyDoseStatusStore.setSkippedDoses(skippedDoseKeys)
    }

    private func doseKey(time: Date, medID: String) -> String {
        NotificationsManager.medicationDoseKey(medID: medID, scheduledAt: time)
    }

    private var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }
}
