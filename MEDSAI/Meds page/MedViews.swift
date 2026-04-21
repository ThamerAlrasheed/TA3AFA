import SwiftUI
import PhotosUI
import Combine
import Foundation

// MARK: - Local model (Postgres-backed via Supabase)
struct LocalMed: Identifiable, Hashable, Equatable {
    let id: String
    var name: String
    var dosage: String
    var frequencyPerDay: Int
    var startDate: Date
    var endDate: Date
    var foodRule: FoodRule
    var notes: String?
    var ingredients: [String]?
    var minIntervalHours: Int?
    var isArchived: Bool
    var catalogId: String? // The UUID from the global medications catalog


    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        frequencyPerDay: Int,
        startDate: Date,
        endDate: Date,
        foodRule: FoodRule = .none,
        notes: String? = nil,
        ingredients: [String]? = nil,
        minIntervalHours: Int? = nil,
        isArchived: Bool = false,
        catalogId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = startDate
        self.endDate = endDate
        self.foodRule = foodRule
        self.notes = notes
        self.ingredients = ingredients
        self.minIntervalHours = minIntervalHours
        self.isArchived = isArchived
        self.catalogId = catalogId
    }

    /// Decode from Supabase row
    struct DBRow: Decodable {
        let id: String
        let dosage: String
        let frequency_per_day: Int
        let frequency_hours: Int?
        let start_date: String?
        let end_date: String?
        let notes: String?
        let is_active: Bool
        let medication_id: String?
        // Joined medication name
        struct MedRef: Decodable { let name: String; let food_rule: String? }
        let medications: MedRef?
    }

    init?(row: DBRow) {
        self.id = row.id
        self.dosage = row.dosage
        self.frequencyPerDay = row.frequency_per_day
        self.minIntervalHours = row.frequency_hours
        self.notes = row.notes
        self.isArchived = !row.is_active
        self.name = row.medications?.name ?? "Unknown"
        self.catalogId = row.medication_id

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        self.startDate = df.date(from: row.start_date ?? "") ?? Date()
        self.endDate = df.date(from: row.end_date ?? "") ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        let frRaw = row.medications?.food_rule ?? FoodRule.none.rawValue
        self.foodRule = FoodRule(rawValue: frRaw) ?? .none
        self.ingredients = nil
    }
}

// MARK: - Repo (per-user, Supabase-backed)
@MainActor
final class UserMedsRepo: ObservableObject {
    private struct UserMedicationUpsertPayload: Encodable {
        let id: String
        let user_id: String
        let medication_id: String
        let dosage: String
        let frequency_per_day: Int
        let frequency_hours: Int?
        let start_date: String
        let end_date: String
        let notes: String?
        let is_active: Bool
    }

    private struct ArchivePayload: Encodable {
        let is_active: Bool
    }

    @Published private(set) var meds: [LocalMed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var canAddMeds = true
    @Published private(set) var notifyMeds = true
    @Published private(set) var notifyAppointments = true

    private var supabase: SupabaseManager { .shared }
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseContextChanged"))
            .sink { [weak self] _ in Task { await self?.fetchMeds() } }
            .store(in: &cancellables)
    }

    func start() {
        isSignedIn = supabase.currentUserID != nil
        guard isSignedIn else { meds = []; errorMessage = nil; return }
        Task { await fetchMeds() }
    }

    func fetchMeds() async {
        guard let uid = supabase.currentUserID else { return }
        let uidString = uid.uuidString.lowercased()
        isLoading = true; errorMessage = nil
        do {
            // 1. Fetch Permission if needed (Only for patients or impersonated contexts)
            if uid != supabase.authenticatedUserID || supabase.isPatientMode {
                struct PermissionRow: Decodable {
                    let can_patient_add_meds: Bool
                    let notify_patient_meds: Bool
                    let notify_patient_appointments: Bool
                }
                let perms: [PermissionRow] = try await self.supabase.retry {
                    try await self.supabase.client
                        .from("caregiver_relations")
                        .select("can_patient_add_meds, notify_patient_meds, notify_patient_appointments")
                        .eq("patient_id", value: uidString)
                        .execute()
                        .value
                }
                
                if let first = perms.first {
                    self.canAddMeds = first.can_patient_add_meds
                    self.notifyMeds = first.notify_patient_meds
                    self.notifyAppointments = first.notify_patient_appointments
                } else {
                    self.canAddMeds = true
                    self.notifyMeds = true
                    self.notifyAppointments = true
                }
            } else {
                self.canAddMeds = true
                self.notifyMeds = true
                self.notifyAppointments = true
            }

            // 2. Fetch Meds
            let rows: [LocalMed.DBRow] = try await self.supabase.retry {
                try await self.supabase.client
                    .from("user_medications")
                    .select("*, medications(name, food_rule)")
                    .eq("user_id", value: uidString)
                    .eq("is_active", value: true)
                    .execute()
                    .value
            }
            self.meds = rows.compactMap { LocalMed(row: $0) }
        } catch {
            print("⚠️ fetchMeds failed for \(uidString):", error)
            errorMessage = "Unable to fetch medications (\(error.localizedDescription))."
        }
        isLoading = false
    }

    // MARK: - CRUD

    func add(_ med: LocalMed) async {
        guard let uid = supabase.currentUserID else { return }
        let uidString = uid.uuidString.lowercased()
        
        // 1. Ensure we have a medication_id to link to
        var finalMedId = med.catalogId
        
        // 1.1 Fallback: if somehow search didn't provide an ID, do a quick lookup by name
        if finalMedId == nil {
            struct MedIdRow: Decodable { let id: String }
            let lookup: [MedIdRow] = (try? await supabase.client
                .from("medications")
                .select("id")
                .ilike("name", value: med.name)
                .limit(1)
                .execute()
                .value) ?? []
            finalMedId = lookup.first?.id
        }
        
        guard let medIdToLink = finalMedId else {
            errorMessage = "Medication '\(med.name)' not found in the global catalog. Please search for it first."
            return
        }

        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withFullDate]

            let row = UserMedicationUpsertPayload(
                id: med.id,
                user_id: uidString,
                medication_id: medIdToLink,
                dosage: med.dosage,
                frequency_per_day: med.frequencyPerDay,
                frequency_hours: med.minIntervalHours,
                start_date: isoFmt.string(from: med.startDate),
                end_date: isoFmt.string(from: med.endDate),
                notes: normalizedNotes(med.notes),
                is_active: true
            )

            try await supabase.client
                .from("user_medications")
                .upsert(row)
                .execute()

            await fetchMeds()
        } catch {
            print("⚠️ add med failed:", error)
            errorMessage = error.localizedDescription
        }
    }

    func update(_ med: LocalMed) async { await add(med) }

    func delete(_ med: LocalMed) async {
        do {
            try await supabase.client
                .from("user_medications")
                .delete()
                .eq("id", value: med.id)
                .execute()
            await fetchMeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setArchived(_ med: LocalMed, archived: Bool) async {
        do {
            try await supabase.client
                .from("user_medications")
                .update(ArchivePayload(is_active: !archived))
                .eq("id", value: med.id)
                .execute()
            await fetchMeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Meds tab (per-user via Firestore)
struct MedListView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var repo = UserMedsRepo()

    @State private var showingAdd = false
    @State private var analyzedPayload: DrugPayload? = nil
    @State private var isPresentingPhotoPicker = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showUploadReview = false

    @State private var editMed: LocalMed? = nil
    @State private var infoMed: LocalMed? = nil
    @State private var toDelete: LocalMed? = nil

    private func menuIcon(_ systemName: String) -> Image {
        let base = UIImage(systemName: systemName)!
        let ui = base.withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        return Image(uiImage: ui).renderingMode(.original)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !repo.isSignedIn {
                    ContentUnavailableView("Sign in required",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("Please log in to view and manage your medications."))
                } else if repo.isLoading {
                    ProgressView("Loading medications…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = repo.errorMessage {
                    ContentUnavailableView("Couldn’t load medications",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err))
                } else {
                    List {
                        if repo.meds.isEmpty {
                            Text("No medications yet. Tap + to add.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(repo.meds, id: \.id) { med in
                            MedRowView(med: med) {
                                editMed = med
                            } onInfo: {
                                infoMed = med
                            } onDelete: {
                                toDelete = med
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Meds")
            .toolbar {
                if repo.canAddMeds || settings.role == .caregiver {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showingAdd = true } label: {
                                HStack { Text("Add Manually"); Spacer(minLength: 8); menuIcon("square.and.pencil") }
                            }
                            Button { isPresentingPhotoPicker = true } label: {
                                HStack { Text("Upload Med Picture"); Spacer(minLength: 8); menuIcon("photo.on.rectangle") }
                            }
                            Button { /* camera later */ } label: {
                                HStack { Text("Take a Picture of the Med"); Spacer(minLength: 8); menuIcon("camera") }
                            }
                        } label: { Image(systemName: "plus.circle.fill") }
                    }
                }
            }

            // Edit sheet
            .sheet(item: $editMed) { med in
                NavigationStack {
                    EditLocalMedView(med: med) { updated in
                        Task { await repo.update(updated) }
                    }
                    .navigationTitle("Edit \(med.name)")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            // Upload photo review
            .sheet(isPresented: $showUploadReview) {
                if let img = selectedImage {
                    UploadPhotoView(image: img) { payload in
                        analyzedPayload = payload
                        selectedImage = nil
                        showingAdd = true
                    } onCancel: {
                        selectedImage = nil
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker,
                          selection: $selectedItem,
                          matching: .images,
                          photoLibrary: .shared())
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        showUploadReview = true
                    }
                    selectedItem = nil
                }
            }

            // Info sheet
            .sheet(item: $infoMed) { med in
                NavigationStack {
                    MedDetailView(medName: med.name, catalogId: med.catalogId)
                        .navigationTitle("Details")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            // Add sheet
            .sheet(isPresented: $showingAdd, onDismiss: { analyzedPayload = nil }) {
                AddLocalMedView(initialPayload: analyzedPayload) { newMed in
                    Task { await repo.add(newMed) }
                }
                .presentationDetents([.medium, .large])
            }


            // Delete confirmation
            .alert("Delete this medication?",
                   isPresented: .constant(toDelete != nil),
                   presenting: toDelete) { med in
                Button("Delete", role: .destructive) {
                    if let m = toDelete {
                        Task { await repo.delete(m) }
                    }
                    toDelete = nil
                }
                Button("Cancel", role: .cancel) { toDelete = nil }
            } message: { med in
                Text("“\(med.name)” and its scheduled doses will be removed.")
            }
            .onAppear { repo.start() }
        }
    }
}

// MARK: - Row extracted to avoid complex type-checking
private struct MedRowView: View {
    @EnvironmentObject var settings: AppSettings
    let med: LocalMed
    let onEdit: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(med.name).font(.headline)
                let subtitle = "\(med.dosage) • \(med.frequencyPerDay)x/day • \(med.foodRule.label)"
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu {
                if settings.role != .patient {
                    Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                }
                Button(action: onInfo) { Label("More information", systemImage: "info.circle") }
                
                if settings.role != .patient {
                    Divider()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Add (GPT + catalog upsert)
struct AddLocalMedView: View {
    var initialPayload: DrugPayload? = nil
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    // Form
    @State private var name: String
    @State private var dosageAmount: Double?
    @State private var dosageUnit: DosageUnit
    @State private var freq: Int
    @State private var start = Date()
    @State private var end: Date
    @State private var notes: String

    // GPT
    @State private var isLoadingInfo = false
    @State private var infoChips: [String]
    @State private var parsedFoodRule: FoodRule
    @State private var parsedMinInterval: Int?
    @State private var catalogId: String? // Captured UUID

    // Strengths from GPT
    @State private var dosageOptions: [String]
    
    init(initialPayload: DrugPayload? = nil, onSave: @escaping (LocalMed) -> Void) {
        self.initialPayload = initialPayload
        self.onSave = onSave
        
        let p = initialPayload
        _name = State(initialValue: p?.title ?? "")
        _dosageAmount = State(initialValue: nil) // will be picked from options
        _dosageUnit = State(initialValue: .mg)
        _freq = State(initialValue: 2)
        _end = State(initialValue: Calendar.current.date(byAdding: .day, value: 14, to: Date())!)
        _notes = State(initialValue: "")
        
        // GPT results pre-fill
        _infoChips = State(initialValue: p?.indications ?? [])
        _dosageOptions = State(initialValue: p?.strengths ?? [])
        
        let food: FoodRule = {
            switch p?.foodRule {
            case "afterFood": return .afterFood
            case "beforeFood": return .beforeFood
            default: return .none
            }
        }()
        _parsedFoodRule = State(initialValue: food)
        _parsedMinInterval = State(initialValue: p?.minIntervalHours)
        _catalogId = State(initialValue: p?.id?.uuidString)
    }
    @State private var selectedDosageOption: String? = nil

    // debounce
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var lastFetchedName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: name) { _, new in scheduleLookup(for: new) }

                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )

                    if !dosageOptions.isEmpty {
                        DosePicker(options: dosageOptions, selection: $selectedDosageOption)
                    } else {
                        DoseManual(amount: $dosageAmount, unit: $dosageUnit)
                    }

                    Stepper("\(freq)x per day", value: $freq, in: 1...6)

                    if isLoadingInfo {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Getting drug info…").foregroundStyle(.secondary)
                        }
                    } else if !infoChips.isEmpty {
                        WrapChips(items: infoChips)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }

                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let strengthOK = (!dosageOptions.isEmpty && (selectedDosageOption ?? dosageOptions.first) != nil)
            || (dosageOptions.isEmpty && dosageAmount != nil)
        return hasName && strengthOK && start <= end
    }

    private func save() {
        let dosageString: String = {
            if !dosageOptions.isEmpty {
                return (selectedDosageOption ?? dosageOptions.first!) // safe by canSave
            } else {
                let amount = dosageAmount ?? 0
                return formatDosage(amount: amount, unit: dosageUnit)
            }
        }()

        let med = LocalMed(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosageString,
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,
            notes: notes.isEmpty ? nil : notes,
            ingredients: nil,
            minIntervalHours: parsedMinInterval,
            catalogId: catalogId
        )

        onSave(med)
        dismiss()
    }

    // MARK: - GPT lookup helpers
    private func scheduleLookup(for input: String) {
        fetchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            infoChips = []; parsedFoodRule = .none; parsedMinInterval = nil
            dosageOptions = []; selectedDosageOption = nil
            return
        }
        if trimmed.caseInsensitiveCompare(lastFetchedName) == .orderedSame { return }
        fetchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await loadInfo(for: trimmed)
        }
    }

    @MainActor
    private func loadInfo(for medName: String) async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        lastFetchedName = medName
        dosageOptions = []; selectedDosageOption = nil

        do {
            let payload = try await DrugInfo.fetchDetails(name: medName)
            // Strengths
            dosageOptions = payload.strengths
            selectedDosageOption = payload.strengths.first

            // Food rule + min interval
            switch (payload.foodRule ?? "none").lowercased() {
            case "afterfood", "after_food": parsedFoodRule = .afterFood
            case "beforefood", "before_food": parsedFoodRule = .beforeFood
            default: parsedFoodRule = .none
            }
            parsedMinInterval = payload.minIntervalHours
            catalogId = payload.id?.uuidString

            // Chips
            var chips: [String] = []
            if parsedFoodRule == .afterFood { chips.append("Take after food") }
            if parsedFoodRule == .beforeFood { chips.append("Take before food") }
            if let ih = parsedMinInterval { chips.append("~every \(ih)h") }
            infoChips = chips

        } catch {
            infoChips = ["Couldn’t fetch info"]
        }
    }
}

// Subviews used by AddLocalMedView — keeps type-checking simple
private struct DosePicker: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        let sel = Binding<String>(
            get: { selection ?? options.first ?? "" },
            set: { selection = $0 }
        )
        return Picker("Dose", selection: sel) {
            ForEach(options, id: \.self) { opt in
                Text(opt).tag(opt)
            }
        }
    }
}

private struct DoseManual: View {
    @Binding var amount: Double?
    @Binding var unit: DosageUnit
    var body: some View {
        HStack {
            NumericTextField(value: $amount, placeholder: "Amount", allowsDecimal: true, maxFractionDigits: 2)
                .frame(minWidth: 90)
            Picker("Unit", selection: $unit) {
                ForEach(DosageUnit.allCases) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}

// MARK: - Edit (minimal changes)
struct EditLocalMedView: View {
    var med: LocalMed
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: LocalMed
    @State private var doseAmount: Double? = nil
    @State private var doseUnit: DosageUnit = .mg

    @State private var infoChips: [String] = []

    init(med: LocalMed, onSave: @escaping (LocalMed) -> Void) {
        self.med = med
        self.onSave = onSave
        _working = State(initialValue: med)
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $working.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                DoseManual(amount: $doseAmount, unit: $doseUnit)

                Stepper("\(working.frequencyPerDay)x per day", value: $working.frequencyPerDay, in: 1...6)

                if !infoChips.isEmpty { WrapChips(items: infoChips) }
            }

            Section("Dates") {
                DatePicker("Start", selection: $working.startDate, displayedComponents: .date)
                DatePicker("End", selection: $working.endDate, displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Notes",
                          text: Binding(
                            get: { working.notes ?? "" },
                            set: { working.notes = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
            }
        }
        .onAppear {
            let (amt, unit) = parseDosageToDouble(working.dosage)
            doseAmount = amt; doseUnit = unit
            var chips: [String] = []
            if working.foodRule == .afterFood { chips.append("Take after food") }
            if working.foodRule == .beforeFood { chips.append("Take before food") }
            if let ih = working.minIntervalHours { chips.append("~every \(ih)h") }
            infoChips = chips
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    let amt = doseAmount ?? 0
                    working.dosage = formatDosage(amount: amt, unit: doseUnit)
                    onSave(working)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Details — try catalog first, else GPT then cache
struct MedDetailView: View {
    let medName: String
    var catalogId: String?

    @State private var loading = true
    @State private var payload: DrugPayload?
    @State private var errorText: String?

    var headerTitle: String { payload?.title.isEmpty == false ? payload!.title : medName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView("Loading info…")
                } else if let p = payload {
                    Text(headerTitle).font(.largeTitle).bold().padding(.bottom, 4)

                    if !p.strengths.isEmpty { WrapChips(items: p.strengths) }

                    // Rules section with human-readable labels
                    let foodLabel: String? = {
                        switch p.foodRule {
                        case "afterFood", "after_food": return "Take after eating"
                        case "beforeFood", "before_food": return "Take before eating"
                        case "none": return nil
                        default: return p.foodRule
                        }
                    }()
                    let ruleItems = [foodLabel, p.minIntervalHours.map { "Minimum interval: \($0)h" }].compactMap { $0 }
                    if !ruleItems.isEmpty { InfoSection(title: "Rules", bullets: ruleItems) }

                    if !p.indications.isEmpty { InfoSection(title: "What it’s for", bullets: p.indications) }
                    if !p.howToTake.isEmpty { InfoSection(title: "How to take", bullets: p.howToTake) }
                    if !p.interactionsToAvoid.isEmpty { InfoSection(title: "Don’t mix with", bullets: p.interactionsToAvoid) }
                    if !p.commonSideEffects.isEmpty { InfoSection(title: "Common side effects", bullets: p.commonSideEffects) }
                    if !p.importantWarnings.isEmpty { InfoSection(title: "Important warnings", bullets: p.importantWarnings) }

                    Text("Source: AI-extracted drug information. Educational only — not medical advice.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                } else if let e = errorText {
                    ContentUnavailableView("No information", systemImage: "doc.text.magnifyingglass", description: Text(e))
                        .padding(.top, 16)
                }
            }
            .padding()
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func loadFromCatalog() async -> DrugPayload? {
        struct CatalogRow: Decodable {
            let id: String
            let name: String
            let food_rule: String?
            let min_interval_hours: Int?
            let interactions_to_avoid: [String]?
            let common_side_effects: [String]?
            let how_to_take: [String]?
            let strengths: [String]?
            let what_for: [String]?
            let rxcui: String?
        }
        do {
            var query = SupabaseManager.shared.client.from("medications").select()
            
            if let cid = catalogId {
                query = query.eq("id", value: cid)
            } else {
                query = query.ilike("name", value: medName)
            }
            
            let rows: [CatalogRow] = try await query
                .limit(1)
                .execute()
                .value
            
            guard let row = rows.first else { return nil }
            
            return DrugPayload(
                title: row.name,
                strengths: row.strengths ?? [],
                dosageForms: [],
                foodRule: row.food_rule,
                minIntervalHours: row.min_interval_hours,
                ingredients: [],
                indications: row.what_for ?? [],
                howToTake: row.how_to_take ?? [],
                commonSideEffects: row.common_side_effects ?? [],
                importantWarnings: [],
                interactionsToAvoid: row.interactions_to_avoid ?? [],
                references: nil,
                kbKey: nil,
                rxcui: row.rxcui,
                id: UUID(uuidString: row.id)
            )
        } catch { return nil }
    }

    private func load() async {
        loading = true; defer { loading = false }

        // 1) Try catalog by catalogId, then by medName
        if let p = await loadFromCatalog() {
            self.payload = p; return
        }

        // 2) AI Fallback
        do {
            let p = try await DrugInfo.fetchDetails(name: medName)
            self.payload = p
        } catch {
            errorText = "Could not find information for \(medName)."
        }
    }
}


// MARK: - Small reusable views
private struct InfoSection: View {
    let title: String
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bullets.prefix(8), id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").bold()
                        Text(line)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct WrapChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items: items) { text in
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

private struct FlexibleWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack { GeometryReader { geo in self.generateContent(in: geo) } }
            .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) { width = 0; height -= d.height }
                        let result = width
                        if item == items.last! { width = 0 } else { width -= d.width }
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        if item == items.last! { height = 0 }
                        return result
                    }
            }
        }
        .background(viewHeightReader($totalHeight))
    }

    private func viewHeightReader(_ binding: Binding<CGFloat>) -> some View {
        GeometryReader { geo -> Color in
            DispatchQueue.main.async { binding.wrappedValue = geo.size.height }
            return .clear
        }
    }
}

// MARK: - Upload review (restored)
struct UploadPhotoView: View {
    let image: UIImage
    var onDone: ((DrugPayload) -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var isAnalyzing = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .blur(radius: isAnalyzing ? 3 : 0)
                    
                    if isAnalyzing {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Analyzing Medication...")
                                .font(.headline)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                
                if let error = errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Review Photo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                    .disabled(isAnalyzing)
                }
                ToolbarItem(placement: .topBarTrailing) {   
                    Button("Analyze") {
                        analyze()
                    }
                    .bold()
                    .disabled(isAnalyzing)
                }
            }
        }
    }
    
    private func analyze() {
        guard let base64 = image.toBase64() else {
            errorMessage = "Failed to process image."
            return
        }
        
        isAnalyzing = true
        errorMessage = nil
        
        Task {
            do {
                let payload = try await DrugInfo.analyzeImage(base64: base64)
                await MainActor.run {
                    isAnalyzing = false
                    onDone?(payload)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = "Analysis failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
