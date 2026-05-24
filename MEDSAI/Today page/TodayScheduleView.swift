import SwiftUI
import UserNotifications

/// "Today" page backed by the shared daily board used by Calendar.
struct TodayScheduleView: View {
    @EnvironmentObject var settings: AppSettings

    @StateObject private var medsRepo = UserMedsRepo()
    @StateObject private var apptsRepo = AppointmentsRepo()

    @State private var today: Date = Date()
    @State private var todaysDoses: [(Date, LocalMed)] = []
    @State private var completedAppointments: Set<String> = CompletionStore.completedAppointments()
    @State private var completedDoseKeys: Set<String> = CompletionStore.completedDoses()
    @State private var skippedDoseKeys: Set<String> = DailyDoseStatusStore.skippedDoses()
    @State private var viewingAppointment: Appointment? = nil
    @State private var viewingMedication: LocalMed? = nil
    @State private var hasLoadedSchedule = false
    @State private var hasLoadedInitially = false
    @State private var isLoadingSchedule = false
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var loadErrorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                content
            }
                .navigationTitle(isArabic ? "اليوم" : "Today")
                .navigationBarTitleDisplayMode(.inline)
                .refreshable {
                    await reloadToday(reason: "manual_refresh")
                }
                .toolbar {
                    if settings.role == .caregiver {
                        ToolbarItem(placement: .topBarLeading) {
                            CareProfileMenu {
                                startTodayLoad(reason: "profile_switch_menu")
                            }
                            .environmentObject(settings)
                        }
                    }
                }
                .onAppear {
                    today = Calendar.current.startOfDay(for: Date())

                    Task {
                        await NotificationsManager.shared.requestAuthorization()
                    }
                }
                .task {
                    guard !hasLoadedInitially else { return }
                    hasLoadedInitially = true
                    await reloadToday(reason: "initial")
                }
                .onChange(of: medsRepo.meds) { _, _ in recomputeDoses() }
                .onChange(of: settings.activePatientID) { _, _ in
                    startTodayLoad(reason: "active_profile_changed")
                }
                .onReceive(NotificationCenter.default.publisher(for: .medicationsDidChange)) { _ in
                    startTodayLoad(reason: "medications_changed")
                }
                .onChange(of: settings.breakfast) { _, _ in recomputeDoses() }
                .onChange(of: settings.lunch) { _, _ in recomputeDoses() }
                .onChange(of: settings.dinner) { _, _ in recomputeDoses() }
                .onChange(of: settings.bedtime) { _, _ in recomputeDoses() }
                .onChange(of: settings.wakeup) { _, _ in recomputeDoses() }
                .onDisappear {
                    loadTask?.cancel()
                    loadTask = nil
                }
                .sheet(item: $viewingAppointment) { appt in
                    AppointmentDetailSheet(appointment: appt)
                        .presentationDetents([.medium, .large])
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
        if isLoadingSchedule && !hasLoadedSchedule {
            ISTSEHLoadingView(
                message: LoadingMessage.custom("Loading today", "جاري تحميل اليوم").text,
                style: .fullScreen
            )
        } else {
            VStack(spacing: 0) {
                if let loadErrorMessage {
                    Text(loadErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                DailyBoardView(
                    selectedDate: today,
                    medicationGroups: todayMedicationGroups,
                    appointmentGroups: todayAppointmentGroups,
                    onToggleDose: toggleDose,
                    onSkipDose: skipDose,
                    onOpenMedication: openMedication,
                    onToggleAppointment: toggleAppointment,
                    onOpenAppointment: openAppointment
                )
            }
        }
    }

    @MainActor
    private func startTodayLoad(reason: String) {
        if isLoadingSchedule {
            #if DEBUG
            print("Today load skipped because already loading. reason=\(reason)")
            #endif
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            await reloadToday(reason: reason)
        }
    }

    @MainActor
    private func reloadToday(reason: String) async {
        if isLoadingSchedule {
            #if DEBUG
            print("Today reload skipped because already loading. reason=\(reason)")
            #endif
            return
        }

        await loadSchedule(reason: reason)
    }

    @MainActor
    private func loadSchedule(reason: String) async {
        isLoadingSchedule = true
        loadErrorMessage = nil

        #if DEBUG
        print("Today load started:", reason)
        #endif

        defer {
            isLoadingSchedule = false
            hasLoadedSchedule = true
            #if DEBUG
            print("Today load finished:", reason)
            print("Today meds count:", medsRepo.meds.count)
            print("Today appointments count:", apptsRepo.items.count)
            #endif
        }

        today = Calendar.current.startOfDay(for: Date())
        refreshCompletionState()

        await medsRepo.fetchMeds()
        await apptsRepo.fetchAppointments()
        recomputeDoses()

        #if DEBUG
        print("TODAY DEBUG fetched active meds:", medsRepo.meds.count)
        for med in medsRepo.meds {
            print(
                "TODAY MED RAW:",
                "name=", med.name,
                "id=", med.id,
                "isActive=", !med.isArchived,
                "isPRN=", med.asNeeded,
                "scheduleMode=", med.scheduleMode.storageValue,
                "frequencyPerDay=", med.frequencyPerDay,
                "timesPerDay=", med.timesPerDay as Any,
                "dosageTimes=", med.dosageTimes,
                "dosageTimesCount=", med.dosageTimes.count,
                "selectedWeekdays=", med.selectedWeekdays,
                "startDate=", med.startDate,
                "endDate=", med.endDate,
                "remindersEnabled=", med.remindersEnabled
            )
        }
        print("TODAY DEBUG dose items:", todaysDoses.count)
        for item in todaysDoses {
            print("TODAY DOSE ITEM:", "med=", item.1.name, "time=", item.0, "sourceMedID=", item.1.id)
        }
        print("TODAY DEBUG medication groups:", todayMedicationGroups.count)
        #endif

        var failedSections: [String] = []
        if medsRepo.errorMessage != nil { failedSections.append("medications") }
        if apptsRepo.errorMessage != nil { failedSections.append("appointments") }
        if !failedSections.isEmpty {
            loadErrorMessage = "Some schedule data could not be loaded."
        }
    }

    private var todayMedicationGroups: [DailyMedicationGroup] {
        DailyBoardBuilder.buildMedicationGroups(
            medications: medsRepo.meds,
            doseItems: todaysDoses.map(doseDisplayItem),
            for: today
        )
    }

    private var todayAppointmentGroups: [DailyAppointmentGroup] {
        DailyBoardBuilder.buildAppointmentGroups(
            appointments: apptsRepo.appointments(on: today),
            completedAppointmentIDs: completedAppointments,
            for: today
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
        guard medsRepo.isSignedIn else {
            todaysDoses = []
            return
        }

        todaysDoses = MedicationDoseBuilder.dosePairs(
            for: medsRepo.meds,
            on: today,
            settings: settings
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
        viewingMedication = medsRepo.meds.first { $0.id == group.medicationID }
    }

    private func openAppointment(_ item: DailyAppointmentDisplayItem?) {
        guard let item else { return }
        viewingAppointment = apptsRepo.items.first { $0.id == item.appointmentID }
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

enum DailyDoseStatusStore {
    private static let skippedDosesKey = "skippedDoseKeys"

    static func skippedDoses() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: skippedDosesKey) ?? [])
    }

    static func setSkippedDoses(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: skippedDosesKey)
    }
}
