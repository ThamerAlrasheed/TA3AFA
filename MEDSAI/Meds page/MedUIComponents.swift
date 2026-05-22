import SwiftUI
import UIKit

// MARK: - Small reusable views
struct InfoSection: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let title: String
    let bullets: [String]

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        let displayBullets = PatientLabelSanitizer.fallbackBullets(bullets, max: 4)
        VStack(alignment: isRTL ? .trailing : .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .tracking(1)
                .multilineTextAlignment(isRTL ? .trailing : .leading)

            VStack(alignment: isRTL ? .trailing : .leading, spacing: 8) {
                ForEach(displayBullets.prefix(4), id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        if isRTL {
                            Text(line)
                                .font(.subheadline)
                                .lineSpacing(2)
                                .multilineTextAlignment(.trailing)
                            Circle()
                                .fill(Color.istsehGreen)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                        } else {
                            Circle()
                                .fill(Color.istsehGreen)
                                .frame(width: 5, height: 5)
                                .padding(.top, 7)
                            Text(line)
                                .font(.subheadline)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct WrapChips: View {
    let items: [String]
    var body: some View {
        FlexibleWrap(items: items, horizontalSpacing: 8, verticalSpacing: 8) { text in
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.istsehGreen)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.istsehGreenSoft)
                .clipShape(Capsule())
        }
    }
}

// MARK: - Container Shape

enum MedicationContainerShape: String {
    case roundedSquare
    case circle
    case softSquare
    case capsuleHorizontal

    static func resolve(for shapeID: String?) -> MedicationContainerShape {
        let value = shapeID?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch value {
        case "tablet_circle", "capsule_circle":
            return .circle
        case "tablet_soft", "capsule_soft":
            return .softSquare
        case "capsule_horizontal", "capsulehorizontal":
            return .capsuleHorizontal
        default:
            return .roundedSquare
        }
    }
}

// MARK: - Custom Cream Tube Icon

struct CreamTubeIcon: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        let tubeW = size * 0.38
        let tubeH = size * 0.52
        let capW = tubeW * 0.55
        let capH = size * 0.12
        let neckW = tubeW * 0.42
        let neckH = size * 0.08

        ZStack {
            // Tube body
            RoundedRectangle(cornerRadius: tubeW * 0.22, style: .continuous)
                .fill(color)
                .frame(width: tubeW, height: tubeH)

            // Highlight stripe
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: tubeW * 0.25, height: tubeH * 0.55)
                .offset(x: -tubeW * 0.18)

            // Neck
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color.opacity(0.8))
                .frame(width: neckW, height: neckH)
                .offset(y: -(tubeH / 2 + neckH * 0.35))

            // Cap
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.55))
                .frame(width: capW, height: capH)
                .offset(y: -(tubeH / 2 + neckH + capH * 0.2))
        }
    }
}

// MARK: - Medication Visual View

struct MedicationVisualView: View {
    let form: String?
    let shapeID: String?
    let medicationColorID: String?
    let backgroundColorID: String?
    var size: CGFloat = 48

    init(
        form: String? = nil,
        shapeID: String?,
        medicationColorID: String?,
        backgroundColorID: String?,
        size: CGFloat = 48
    ) {
        self.form = form
        self.shapeID = shapeID
        self.medicationColorID = medicationColorID
        self.backgroundColorID = backgroundColorID
        self.size = size
    }

    private var resolvedContainer: MedicationContainerShape {
        MedicationContainerShape.resolve(for: shapeID)
    }

    private var isCreamType: Bool {
        let key = shapeID?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let creamKeys: Set<String> = ["cream", "ointment", "gel", "topical", "lotion", "tube", "cream_tube", "jar"]
        if creamKeys.contains(key) { return true }
        if key.isEmpty, let normalized = MedicationIconSuggestion.normalizedForm(from: form), normalized == "cream" {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            containerBackground
            iconContent
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var containerBackground: some View {
        switch resolvedContainer {
        case .circle:
            Circle()
                .fill(Self.backgroundColor(backgroundColorID, form: form))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: max(size * 0.05, 2), x: 0, y: 1.5)
        case .softSquare:
            RoundedRectangle(cornerRadius: size * 0.38, style: .continuous)
                .fill(Self.backgroundColor(backgroundColorID, form: form))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: max(size * 0.05, 2), x: 0, y: 1.5)
        case .capsuleHorizontal:
            Capsule(style: .continuous)
                .fill(Self.backgroundColor(backgroundColorID, form: form))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: max(size * 0.05, 2), x: 0, y: 1.5)
        case .roundedSquare:
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Self.backgroundColor(backgroundColorID, form: form))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: max(size * 0.05, 2), x: 0, y: 1.5)
        }
    }

    @ViewBuilder
    private var iconContent: some View {
        if isCreamType {
            CreamTubeIcon(
                color: Self.medicationColor(medicationColorID, form: form),
                size: size
            )
        } else {
            Image(systemName: Self.systemImage(for: shapeID, form: form))
                .font(.system(size: size * 0.40, weight: .semibold))
                .foregroundStyle(Self.medicationColor(medicationColorID, form: form))
                .shadow(color: .black.opacity(0.06), radius: 1.5, x: 0, y: 1)
        }
    }

    // MARK: - Symbol Resolver

    static func systemImage(for shapeID: String?, form: String? = nil) -> String {
        let symbol = resolveSymbol(for: shapeID, form: form)
        if UIImage(systemName: symbol) != nil {
            return symbol
        }
        #if DEBUG
        print("⚠️ MedicationVisualView: invalid SF Symbol '\(symbol)' for shapeID=\(shapeID ?? "nil") form=\(form ?? "nil")")
        #endif
        return "pills.fill"
    }

    private static func resolveSymbol(for shapeID: String?, form: String? = nil) -> String {
        if let shape = shapeID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !shape.isEmpty {
            switch shape {
            // Tablets
            case "tablet", "tablet_rounded", "tablet_circle", "tablet_soft", "pill", "pills":
                return "pills.fill"
            case "oval", "oblong":
                return "capsule.fill"
            // Capsules
            case "capsule", "capsule_rounded", "capsule_circle", "capsule_soft":
                return "capsule.fill"
            case "capsulehorizontal", "capsule_horizontal":
                return "capsule.fill"
            // Liquids
            case "liquid", "vial", "dropbottle", "syrup", "solution", "suspension":
                return "cross.vial.fill"
            case "cup":
                return "drop.fill"
            case "spoon":
                return "syringe.fill"
            // Drops
            case "drops", "eye_drops", "ear_drops":
                return "drop.triangle.fill"
            // Injections
            case "syringe", "injection", "injectable":
                return "syringe.fill"
            case "injectionpen":
                return "pencil"
            // Inhalers & Spray
            case "inhaler":
                return "wind"
            case "spray", "nasal_spray":
                return "humidity.fill"
            // Devices
            case "device":
                return "medical.thermometer.fill"
            // Cream/topical — handled by CreamTubeIcon, but if SF symbol is forced:
            case "cream", "ointment", "gel", "topical", "lotion", "tube", "cream_tube", "jar":
                return "cross.case.fill"
            // Patches
            case "patch":
                return "bandage.fill"
            // Suppository
            case "suppository", "diamond":
                return "diamond.fill"
            // Other
            case "other":
                return "ellipsis.circle.fill"
            default:
                break
            }
        }

        // Fallback by medication form
        let normalized = MedicationIconSuggestion.normalizedForm(from: form)
        switch normalized {
        case "tablet": return "pills.fill"
        case "capsule": return "capsule.fill"
        case "liquid": return "cross.vial.fill"
        case "drops": return "drop.triangle.fill"
        case "injection": return "syringe.fill"
        case "inhaler": return "wind"
        case "cream": return "cross.case.fill"
        case "patch": return "bandage.fill"
        default: return "pills.fill"
        }
    }

    // MARK: - Premium Color Palette

    static func medicationColor(_ id: String?, form: String? = nil) -> Color {
        if let id, !id.isEmpty {
            switch id.lowercased() {
            case "green":     return Color(red: 0.18, green: 0.72, blue: 0.44)
            case "sage":      return Color(red: 0.42, green: 0.58, blue: 0.46)
            case "mint":      return Color(red: 0.22, green: 0.70, blue: 0.56)
            case "emerald":   return Color(red: 0.15, green: 0.60, blue: 0.42)
            case "teal":      return Color(red: 0.10, green: 0.56, blue: 0.58)
            case "aqua":      return Color(red: 0.12, green: 0.54, blue: 0.68)
            case "coral":     return Color(red: 0.82, green: 0.38, blue: 0.38)
            case "rose":      return Color(red: 0.78, green: 0.32, blue: 0.46)
            case "peach":     return Color(red: 0.82, green: 0.52, blue: 0.32)
            case "amber":     return Color(red: 0.78, green: 0.58, blue: 0.16)
            case "lavender":  return Color(red: 0.52, green: 0.42, blue: 0.78)
            case "purple":    return Color(red: 0.58, green: 0.36, blue: 0.76)
            case "slate":     return Color(red: 0.38, green: 0.44, blue: 0.52)
            case "neutral":   return Color(red: 0.34, green: 0.38, blue: 0.42)
            case "sand":      return Color(red: 0.62, green: 0.48, blue: 0.32)
            case "white":     return .white
            case "red":       return Color(red: 0.76, green: 0.28, blue: 0.32)
            case "yellow":    return Color(red: 0.78, green: 0.68, blue: 0.22)
            case "blue":      return Color(red: 0.22, green: 0.56, blue: 0.78)
            default:          return Color(red: 0.18, green: 0.72, blue: 0.44)
            }
        }
        // Form-based default colors
        return defaultForeground(for: form)
    }

    static func backgroundColor(_ id: String?, form: String? = nil) -> Color {
        if let id, !id.isEmpty {
            switch id.lowercased() {
            case "softgreen":    return Color(red: 0.91, green: 0.97, blue: 0.93)
            case "softmint":     return Color(red: 0.89, green: 0.97, blue: 0.94)
            case "softsage":     return Color(red: 0.90, green: 0.94, blue: 0.91)
            case "softteal":     return Color(red: 0.88, green: 0.96, blue: 0.96)
            case "softaqua":     return Color(red: 0.89, green: 0.95, blue: 0.97)
            case "softcoral":    return Color(red: 0.98, green: 0.92, blue: 0.92)
            case "softrose":     return Color(red: 0.98, green: 0.91, blue: 0.94)
            case "softpeach":    return Color(red: 1.00, green: 0.94, blue: 0.90)
            case "softamber":    return Color(red: 1.00, green: 0.96, blue: 0.86)
            case "softlavender": return Color(red: 0.94, green: 0.93, blue: 1.00)
            case "softpurple":   return Color(red: 0.95, green: 0.92, blue: 1.00)
            case "softslate":    return Color(red: 0.93, green: 0.94, blue: 0.96)
            case "softsand":     return Color(red: 0.97, green: 0.94, blue: 0.90)
            case "mist":         return Color(red: 0.88, green: 0.94, blue: 0.92)
            case "neutral":      return Color(.secondarySystemBackground)
            case "warm":         return Color(red: 0.98, green: 0.95, blue: 0.88)
            case "blush":        return Color(red: 0.98, green: 0.92, blue: 0.93)
            case "dark":         return Color(red: 0.10, green: 0.14, blue: 0.20)
            default:             return Color(red: 0.91, green: 0.97, blue: 0.93)
            }
        }
        // Form-based default backgrounds
        return defaultBackground(for: form)
    }

    // MARK: - Form-Based Default Colors

    private static func defaultForeground(for form: String?) -> Color {
        let normalized = MedicationIconSuggestion.normalizedForm(from: form) ?? ""
        switch normalized {
        case "tablet":    return Color(red: 0.18, green: 0.72, blue: 0.44) // green
        case "capsule":   return Color(red: 0.10, green: 0.56, blue: 0.58) // teal
        case "liquid":    return Color(red: 0.12, green: 0.54, blue: 0.68) // aqua
        case "drops":     return Color(red: 0.12, green: 0.54, blue: 0.68) // aqua
        case "cream":     return Color(red: 0.82, green: 0.52, blue: 0.32) // peach
        case "injection": return Color(red: 0.78, green: 0.32, blue: 0.46) // rose
        case "inhaler":   return Color(red: 0.10, green: 0.56, blue: 0.58) // teal
        case "patch":     return Color(red: 0.52, green: 0.42, blue: 0.78) // lavender
        default:          return Color(red: 0.18, green: 0.72, blue: 0.44) // green
        }
    }

    private static func defaultBackground(for form: String?) -> Color {
        let normalized = MedicationIconSuggestion.normalizedForm(from: form) ?? ""
        switch normalized {
        case "tablet":    return Color(red: 0.91, green: 0.97, blue: 0.93) // softGreen
        case "capsule":   return Color(red: 0.88, green: 0.96, blue: 0.96) // softTeal
        case "liquid":    return Color(red: 0.89, green: 0.95, blue: 0.97) // softAqua
        case "drops":     return Color(red: 0.89, green: 0.95, blue: 0.97) // softAqua
        case "cream":     return Color(red: 1.00, green: 0.94, blue: 0.90) // softPeach
        case "injection": return Color(red: 0.98, green: 0.91, blue: 0.94) // softRose
        case "inhaler":   return Color(red: 0.88, green: 0.96, blue: 0.96) // softTeal
        case "patch":     return Color(red: 0.94, green: 0.93, blue: 1.00) // softLavender
        default:          return Color(red: 0.91, green: 0.97, blue: 0.93) // softGreen
        }
    }
}

enum MedicationIconSuggestion {
    static func normalizedForm(from value: String?) -> String? {
        let normalized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "_", with: " ")
        guard !normalized.isEmpty else { return nil }

        if containsAny(normalized, terms: ["tablet", "tablets", "tab", "أقراص", "قرص"]) { return "tablet" }
        if containsAny(normalized, terms: ["capsule", "capsules", "cap", "كبسولة", "كبسولات"]) { return "capsule" }
        if containsAny(normalized, terms: ["syrup", "oral solution", "suspension", "شراب", "محلول"]) { return "liquid" }
        if containsAny(normalized, terms: ["drops", "eye drops", "ear drops", "ophthalmic", "قطرات", "قطرة", "للعين"]) { return "drops" }
        if containsAny(normalized, terms: ["cream", "ointment", "gel", "كريم", "مرهم", "جل"]) { return "cream" }
        if containsAny(normalized, terms: ["inhaler", "بخاخ"]) { return "inhaler" }
        if containsAny(normalized, terms: ["injection", "vial", "ampoule", "ampule", "حقن", "فيال", "أمبول"]) { return "injection" }
        if containsAny(normalized, terms: ["patch", "لصقة"]) { return "patch" }
        return nil
    }

    static func suggestedShapeID(for form: String?) -> String? {
        switch normalizedForm(from: form) {
        case "tablet": return "tablet"
        case "capsule": return "capsule"
        case "liquid": return "liquid"
        case "drops": return "drops"
        case "cream": return "tube"
        case "inhaler": return "inhaler"
        case "injection": return "syringe"
        case "patch": return "patch"
        default: return nil
        }
    }

    static func displayName(for form: String?) -> String? {
        switch normalizedForm(from: form) {
        case "tablet": return "Tablet"
        case "capsule": return "Capsule"
        case "liquid": return "Syrup"
        case "drops": return "Drops"
        case "cream": return "Tube"
        case "inhaler": return "Inhaler"
        case "injection": return "Injection"
        case "patch": return "Patch"
        default: return nil
        }
    }

    private static func containsAny(_ value: String, terms: [String]) -> Bool {
        terms.contains { value.contains($0) }
    }
}

struct FlexibleWrap<Content: View>: View {
    let items: [String]
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            VStack {
                GeometryReader { geo in self.generateContent(in: geo) }
            }
            .frame(height: totalHeight)
        }
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > g.size.width {
                            width = 0
                            height -= d.height + verticalSpacing
                        }
                        let result = width
                        if item == items.last! {
                            width = 0
                        } else {
                            width -= d.width + horizontalSpacing
                        }
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
