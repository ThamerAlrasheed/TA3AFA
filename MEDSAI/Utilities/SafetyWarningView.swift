import SwiftUI

struct SafetyWarningVisual {
    let iconName: String
    let color: Color
    let label: String
    let title: String
    let meaning: String
    let priority: Int
    let accessibilityLabel: String
}

enum SafetyWarningPresentation {
    static func visual(for warning: SafetyWarning) -> SafetyWarningVisual {
        let severityRank = rank(for: warning.severity)
        let color = color(for: warning)

        switch warning.type {
        case .allergyConflict:
            return SafetyWarningVisual(
                iconName: "exclamationmark.triangle.fill",
                color: .red,
                label: "Allergy",
                title: "Allergy conflict",
                meaning: "Allergy conflict / contraindicated",
                priority: severityRank,
                accessibilityLabel: "Safety warning: Allergy conflict"
            )
        case .drugInteraction:
            return SafetyWarningVisual(
                iconName: "arrow.triangle.2.circlepath",
                color: color,
                label: "Interaction",
                title: "Medication interaction",
                meaning: "Medication interaction warning",
                priority: severityRank + 1,
                accessibilityLabel: "Safety warning: Medication interaction"
            )
        case .duplicateIngredient:
            return SafetyWarningVisual(
                iconName: "doc.on.doc.fill",
                color: color,
                label: "Duplicate",
                title: "Duplicate ingredient",
                meaning: "Same or overlapping active ingredient",
                priority: severityRank + 2,
                accessibilityLabel: "Safety warning: Duplicate ingredient"
            )
        case .conditionConflict:
            return SafetyWarningVisual(
                iconName: "heart.text.square.fill",
                color: .purple,
                label: "Condition",
                title: "Condition warning",
                meaning: "Chronic condition warning",
                priority: severityRank + 3,
                accessibilityLabel: "Safety warning: Chronic condition warning"
            )
        }
    }

    static func sorted(_ warnings: [SafetyWarning]) -> [SafetyWarning] {
        warnings.sorted { visual(for: $0).priority < visual(for: $1).priority }
    }

    static func rank(for severity: SafetySeverity) -> Int {
        switch severity {
        case .contraindicated: return 0
        case .major: return 10
        case .moderate: return 20
        case .minor: return 30
        case .unknown: return 40
        }
    }

    static func color(for warning: SafetyWarning) -> Color {
        switch warning.type {
        case .allergyConflict:
            return .red
        case .drugInteraction:
            switch warning.severity {
            case .contraindicated: return .red
            case .major: return .orange
            case .moderate: return .yellow
            case .minor: return Color.istsehGreen
            case .unknown: return .gray
            }
        case .duplicateIngredient:
            switch warning.severity {
            case .contraindicated: return .red
            case .major: return .orange
            case .moderate: return .yellow
            case .minor: return .yellow
            case .unknown: return .gray
            }
        case .conditionConflict:
            return .purple
        }
    }
}

struct SafetyWarningBadge: View {
    let warning: SafetyWarning
    let additionalCount: Int
    let onTap: () -> Void

    var body: some View {
        let visual = SafetyWarningPresentation.visual(for: warning)

        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: visual.iconName)
                    .imageScale(.small)
                Text(visual.label)
                    .fontWeight(.semibold)
                if additionalCount > 0 {
                    Text("+\(additionalCount)")
                        .fontWeight(.bold)
                        .padding(.leading, 2)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(visual.color)
            .background(visual.color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(visual.color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(visual.title): \(warning.description)")
        .contextMenu {
            Button(action: onTap) {
                Label("View warning details", systemImage: "info.circle")
            }
        }
        .accessibilityLabel(Text(visual.accessibilityLabel))
        .accessibilityValue(Text(additionalCount > 0 ? "\(additionalCount + 1) warnings" : warning.severity.rawValue))
        .accessibilityHint(Text("Opens safety warning details"))
    }
}

struct SafetyWarningView: View {
    let warnings: [SafetyWarning]
    let offlineMessage: String?
    var sourceTrace: [String] = []
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let offline = offlineMessage {
                        HStack {
                            Image(systemName: "wifi.slash")
                            Text(offline)
                        }
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }

                    ForEach(SafetyWarningPresentation.sorted(warnings)) { warning in
                        warningCard(warning)
                    }
                }
                .padding()
            }
            .navigationTitle("Safety Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Go Back") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    let isContraindicated = warnings.contains { $0.severity == .contraindicated || !$0.can_continue }

                    if isContraindicated {
                        VStack(spacing: 8) {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text("Safety Block: Contraindicated")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text("This medication combination is unsafe and cannot be added. Please consult a doctor immediately.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.red.opacity(0.05))
                        .cornerRadius(12)

                        Button(action: {
                            onCancel()
                            dismiss()
                        }) {
                            Text("Go Back")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.istsehGreen)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    } else {
                        let isMajor = warnings.contains { $0.severity == .major }

                        Button(action: {
                            onConfirm()
                            dismiss()
                        }) {
                            Text(isMajor ? "I Understand, Save Anyway" : "Continue")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isMajor ? Color.orange : Color.istsehGreen)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }

    private func warningCard(_ warning: SafetyWarning) -> some View {
        let visual = SafetyWarningPresentation.visual(for: warning)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: visual.iconName)
                    .foregroundColor(visual.color)
                Text(visual.label)
                    .font(.caption)
                    .bold()
                    .foregroundColor(visual.color)
                Spacer()
                Text(warning.severity.rawValue.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(visual.color.opacity(0.2))
                    .foregroundColor(visual.color)
                    .cornerRadius(4)
            }

            Text(warning.description)
                .font(.body)
                .bold()

            if let management = warning.management {
                Text(management)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !warning.meds.isEmpty {
                Text("Involved: " + warning.meds.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Text(visual.meaning)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.istsehCard)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(visual.color.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(visual.accessibilityLabel))
    }
}

struct SafetyWarningDetailView: View {
    let warning: SafetyWarning
    let sourceTrace: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let visual = SafetyWarningPresentation.visual(for: warning)

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: visual.iconName)
                                .font(.title2)
                                .foregroundStyle(visual.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visual.title)
                                    .font(.headline)
                                Text(visual.meaning)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(warning.severity.rawValue.uppercased())
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .foregroundStyle(visual.color)
                                .background(visual.color.opacity(0.16))
                                .clipShape(Capsule())
                        }

                        Text(warning.description)
                            .font(.body)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(visual.color.opacity(0.08))

                Section("Affected medication(s)") {
                    Text(warning.meds.isEmpty ? "Not specified" : warning.meds.joined(separator: ", "))
                }

                if let management = warning.management, !management.isEmpty {
                    Section("Management") {
                        Text(management)
                    }
                }

                Section("Source") {
                    LabeledContent("Source", value: warning.source)
                    LabeledContent("Deterministic", value: warning.is_deterministic ? "Yes" : "No")
                    LabeledContent("Can continue", value: warning.can_continue ? "Yes" : "No")
                    LabeledContent("Acknowledgement", value: warning.requires_acknowledgement ? "Required" : "Not required")
                }

                if !sourceTrace.isEmpty {
                    Section("Source trace") {
                        Text(sourceTrace.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Warning Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .accessibilityLabel(Text(visual.accessibilityLabel))
    }
}
