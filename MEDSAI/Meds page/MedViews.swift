import SwiftUI
import PhotosUI
import Combine
import Foundation

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
                            MedRowView(med: med,
                                      onEdit: { editMed = med },
                                      onInfo: { infoMed = med },
                                      onDelete: { toDelete = med })
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
                
                // Ensure it's in the global catalog so we have a UUID
                let entry = try? await MedCatalogRepo.shared.upsert(from: payload, searchedName: payload.title)
                let finalPayload = entry?.payload ?? payload

                await MainActor.run {
                    isAnalyzing = false
                    onDone?(finalPayload)
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
