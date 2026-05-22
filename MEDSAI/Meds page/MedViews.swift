import SwiftUI
import PhotosUI
import Combine
import Foundation
import AVFoundation
import UIKit

// MARK: - Meds tab (per-user via Firestore)
struct MedListView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject private var repo: UserMedsRepo
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance.language") private var languageCode: String = "en"

    private var isArabic: Bool { languageCode == "ar" }

    @State private var showingAdd = false
    @State private var analyzedPayload: DrugPayload? = nil
    @State private var analyzedScanMetadata: MedicationScanSaveMetadata? = nil
    @State private var isPresentingPhotoPicker = false
    @State private var isPresentingCamera = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var scanImageBundle: MedicationScanImageBundle?
    @State private var showUploadReview = false
    @State private var cameraAlert: CameraAccessAlert?

    @State private var editMed: LocalMed? = nil
    @State private var infoMed: LocalMed? = nil
    @State private var toDelete: LocalMed? = nil
    @State private var selectedSafetyWarning: SelectedSafetyWarning?

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
                } else if repo.isLoading && !repo.hasLoadedOnce && repo.meds.isEmpty {
                    BrandedLoadingView(message: LoadingMessage.medications.text, style: .fullScreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = repo.errorMessage, repo.meds.isEmpty {
                    ContentUnavailableView("Couldn't load medications",
                        systemImage: "exclamationmark.triangle",
                        description: Text(err))
                } else {
                    List {
                        if repo.meds.isEmpty && repo.hasLoadedOnce {
                            Text("No medications yet. Tap + to add.")
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.istsehCard)
                        }

                        ForEach(repo.meds, id: \.id) { med in
                            MedRowView(med: med,
                                      warnings: repo.safetyWarnings(for: med),
                                      onEdit: { editMed = med },
                                      onInfo: { infoMed = med },
                                      onDelete: { toDelete = med },
                                      onWarningTap: { warning in
                                          selectedSafetyWarning = SelectedSafetyWarning(
                                            warning: warning,
                                            sourceTrace: repo.safetySourceTrace
                                          )
                                      })
                            .listRowBackground(Color.istsehCard)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await repo.fetchMeds()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle(isArabic ? "الأدوية" : "Meds")
            .navigationBarTitleDisplayMode(.inline)
            .avoidsTabBar()
            .toolbar {
                if settings.role == .caregiver {
                    ToolbarItem(placement: .topBarLeading) {
                        CareProfileMenu {
                            repo.start()
                        }
                        .environmentObject(settings)
                    }
                }

                if repo.canAddMeds || settings.role == .caregiver {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { showingAdd = true } label: {
                                HStack { Text("Add Manually"); Spacer(minLength: 8); menuIcon("square.and.pencil") }
                            }
                            Button { isPresentingPhotoPicker = true } label: {
                                HStack { Text("Upload Med Picture"); Spacer(minLength: 8); menuIcon("photo.on.rectangle") }
                            }
                            Button { openCamera() } label: {
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
            .sheet(isPresented: $showUploadReview, onDismiss: {
                scanImageBundle = nil
            }) {
                if let bundle = scanImageBundle {
                    UploadPhotoView(imageBundle: bundle) { payload, metadata in
                        analyzedPayload = payload
                        analyzedScanMetadata = metadata
                        scanImageBundle = nil
                        showingAdd = true
                    } onCancel: {
                        scanImageBundle = nil
                        analyzedScanMetadata = nil
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .photosPicker(isPresented: $isPresentingPhotoPicker,
                          selection: $selectedItem,
                          matching: .images,
                          photoLibrary: .shared())
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraCaptureView { image in
                    scanImageBundle = MedicationScanImageBundle(original: image)
                    showUploadReview = true
                } onError: { message in
                    if message != "cancelled" {
                        cameraAlert = CameraAccessAlert(
                             title: "Camera unavailable",
                             message: friendlyCameraMessage(message),
                             canOpenSettings: message.lowercased().contains("permission"),
                             canChoosePhoto: true
                        )
                    }
                }
            }
            .alert(cameraAlert?.title ?? "Camera", isPresented: Binding(
                get: { cameraAlert != nil },
                set: { if !$0 { cameraAlert = nil } }
            )) {
                if cameraAlert?.canOpenSettings == true {
                    Button("Settings") { openAppSettings() }
                }
                if cameraAlert?.canChoosePhoto == true {
                    Button("Choose Photo") { isPresentingPhotoPicker = true }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text(cameraAlert?.message ?? "")
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        if let rawImage = UIImage(data: data) {
                            scanImageBundle = MedicationScanImageBundle(original: rawImage)
                            showUploadReview = true
                        }
                    }
                    selectedItem = nil
                }
            }

            // Info sheet
            .sheet(item: $infoMed) { med in
                NavigationStack {
                    MedDetailView(medName: med.name, catalogId: med.catalogId, med: med)
                        .navigationTitle("Details")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }

            .sheet(item: $selectedSafetyWarning) { selected in
                SafetyWarningDetailView(
                    warning: selected.warning,
                    sourceTrace: selected.sourceTrace
                )
                .presentationDetents([.medium, .large])
            }

            // Add sheet
            .sheet(isPresented: $showingAdd, onDismiss: {
                analyzedPayload = nil
                analyzedScanMetadata = nil
            }) {
                AddLocalMedView(initialPayload: analyzedPayload, scanMetadata: analyzedScanMetadata) { newMed in
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
            .onChange(of: settings.activePatientID) { _, _ in repo.start() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await repo.fetchMeds() }
                }
            }
            .alert("Save Error", isPresented: Binding(
                get: { repo.saveErrorMessage != nil },
                set: { if !$0 { repo.saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { repo.saveErrorMessage = nil }
            } message: {
                Text(repo.saveErrorMessage ?? "An error occurred while saving.")
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraAlert = CameraAccessAlert(
                title: "Camera unavailable",
                message: "This device does not have an available camera. You can choose a medication photo from your library instead.",
                canOpenSettings: false,
                canChoosePhoto: true
            )
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPresentingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        isPresentingCamera = true
                    } else {
                        cameraAlert = CameraAccessAlert(
                            title: "Camera access disabled",
                            message: "Camera access is disabled. Enable it in Settings to scan medication.",
                            canOpenSettings: true,
                            canChoosePhoto: true
                        )
                    }
                }
            }
        case .denied, .restricted:
            cameraAlert = CameraAccessAlert(
                title: "Camera access disabled",
                message: "Camera access is disabled. Enable it in Settings to scan medication.",
                canOpenSettings: true,
                canChoosePhoto: true
            )
        @unknown default:
            cameraAlert = CameraAccessAlert(
                title: "Camera unavailable",
                message: "We could not open the camera. You can choose a medication photo from your library instead.",
                canOpenSettings: false,
                canChoosePhoto: true
            )
        }
    }

    private func friendlyCameraMessage(_ message: String) -> String {
        if message.lowercased().contains("permission") {
            return "Camera access is disabled. Enable it in Settings to scan medication."
        }
        if message.lowercased().contains("no camera") {
            return "This device does not have an available camera. You can choose a medication photo from your library instead."
        }
        return "We could not open the camera. You can choose a medication photo from your library instead."
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SelectedSafetyWarning: Identifiable {
    let id = UUID()
    let warning: SafetyWarning
    let sourceTrace: [String]
}

private struct CameraAccessAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let canOpenSettings: Bool
    let canChoosePhoto: Bool
}

// MARK: - Row extracted to avoid complex type-checking
private struct MedRowView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.layoutDirection) private var layoutDirection

    let med: LocalMed
    let warnings: [SafetyWarning]
    let onEdit: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void
    let onWarningTap: (SafetyWarning) -> Void

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        let sortedWarnings = SafetyWarningPresentation.sorted(warnings)

        HStack(spacing: 14) {
            MedicationVisualView(
                form: med.medicationForm,
                shapeID: med.visualShape,
                medicationColorID: med.visualColor,
                backgroundColorID: med.visualBackgroundColor,
                size: 56
            )

            VStack(alignment: isRTL ? .trailing : .leading, spacing: 5) {
                Text(med.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let isArabic = UserDefaults.standard.string(forKey: "appearance.language") == "ar"

                // Line 1: clean dose amount (hidden if suspicious/messy)
                if let doseText = DoseTextFormatter.formatDoseAmount(for: med) {
                    Text(doseText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Line 2: schedule frequency or food rule
                let schedule = med.scheduleSummary(isArabic: isArabic)
                let foodVisible = MedicationFormRules.shouldShowFoodTiming(formID: med.medicationForm, foodRule: med.foodRule, sourceBacked: med.foodRuleSource == "source")
                let foodLabel = foodVisible && !(med.scheduleMode.isPRN || med.asNeeded) ? med.foodRuleLabel(isArabic: isArabic) : ""

                if !schedule.isEmpty {
                    Text(schedule)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !foodLabel.isEmpty {
                    Text(foodLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let primaryWarning = sortedWarnings.first {
                    SafetyWarningBadge(
                        warning: primaryWarning,
                        additionalCount: max(sortedWarnings.count - 1, 0),
                        onTap: { onWarningTap(primaryWarning) }
                    )
                    .padding(.top, 2)
                }
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

// MARK: - Upload review (restored)
struct UploadPhotoView: View {
    let imageBundle: MedicationScanImageBundle
    var onDone: ((DrugPayload, MedicationScanSaveMetadata?) -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    
    @State private var isAnalyzing = false
    @State private var errorMessage: String? = nil
    @State private var scanDecision: MedicationScanDecision? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Image(uiImage: imageBundle.previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .blur(radius: isAnalyzing ? 3 : 0)
                    
                    if isAnalyzing {
                        ISTSEHLoadingView(
                            message: LoadingMessage.custom("Analyzing medication", "جاري تحليل الدواء").text,
                            style: .card
                        )
                        .padding(24)
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
            .sheet(item: $scanDecision) { decision in
                MedScanConfirmationView(
                    previewImage: imageBundle.previewImage,
                    fallbackImageDataProvider: { imageBundle.fallbackImageData() },
                    decision: decision,
                    onConfirmed: { finalPayload, metadata in
                        onDone?(finalPayload, metadata)
                        dismiss()
                    },
                    onCancel: {
                        scanDecision = nil
                    }
                )
            }
        }
    }
    
    private func analyze() {
        isAnalyzing = true
        errorMessage = nil
        
        Task {
            do {
                let result = try await MedicationScanPipeline().process(
                    imageBundle: imageBundle,
                    allowGPTResolver: true,
                    allowImageFallback: false
                )
                await MainActor.run {
                    isAnalyzing = false
                    scanDecision = result
                }
            } catch {
                #if DEBUG
                print("Medication local scan failed: \(error)")
                #endif
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = "We could not read enough text from this image. Try better lighting or use AI image recognition."
                }
            }
        }
    }
}

extension ScanResult: Identifiable {
    public var id: String { analysis_id }
}
