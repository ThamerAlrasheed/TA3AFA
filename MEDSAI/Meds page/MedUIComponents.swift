import SwiftUI

// MARK: - Small reusable views
struct InfoSection: View {
    let title: String
    let bullets: [String]
    var body: some View {
        let displayBullets = PatientLabelSanitizer.fallbackBullets(bullets, max: 4)
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .tracking(1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayBullets.prefix(4), id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
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

    var body: some View {
        ZStack {
            Circle()
                .fill(Self.backgroundColor(backgroundColorID))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.10), radius: max(size * 0.06, 3), x: 0, y: 2)

            Image(systemName: Self.systemImage(for: shapeID, form: form))
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(Self.medicationColor(medicationColorID))
                .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    static func systemImage(for shapeID: String?, form: String? = nil) -> String {
        switch shapeID {
        case "tablet": return "circle.fill"
        case "oval", "oblong": return "capsule.fill"
        case "capsule": return "capsule.portrait.fill"
        case "capsuleHorizontal": return "capsule.fill"
        case "liquid", "vial", "dropBottle": return "cross.vial.fill"
        case "cup": return "drop.fill"
        case "spoon": return "syringe.fill"
        case "drops": return "drop.triangle.fill"
        case "syringe": return "syringe.fill"
        case "injectionPen": return "pencil"
        case "inhaler": return "wind"
        case "device": return "medical.thermometer.fill"
        case "tube": return "cross.case.fill"
        case "jar": return "shippingbox.fill"
        case "patch": return "square.fill"
        case "spray": return "spray.fill"
        case "suppository", "diamond": return "diamond.fill"
        default:
            switch form {
            case "capsule": return "capsule.portrait.fill"
            case "liquid": return "cross.vial.fill"
            case "drops": return "drop.triangle.fill"
            case "injection": return "syringe.fill"
            case "inhaler", "spray": return "wind"
            case "patch": return "square.fill"
            case "suppository": return "diamond.fill"
            default: return "pills.fill"
            }
        }
    }

    static func medicationColor(_ id: String?) -> Color {
        switch id {
        case "white": return .white
        case "yellow": return Color(red: 0.88, green: 0.76, blue: 0.30)
        case "red": return Color(red: 0.76, green: 0.28, blue: 0.32)
        case "blue": return .cyan
        case "purple": return .purple
        case "mint": return Color(red: 0.34, green: 0.78, blue: 0.64)
        case "sage": return Color(red: 0.48, green: 0.62, blue: 0.51)
        case "teal": return Color(red: 0.16, green: 0.62, blue: 0.58)
        case "aqua": return Color(red: 0.28, green: 0.72, blue: 0.76)
        case "amber": return Color(red: 0.86, green: 0.62, blue: 0.22)
        case "rose": return Color(red: 0.78, green: 0.36, blue: 0.42)
        case "slate": return Color(red: 0.36, green: 0.43, blue: 0.48)
        case "green": return .istsehGreen
        default: return .istsehGreen
        }
    }

    static func backgroundColor(_ id: String?) -> Color {
        switch id {
        case "neutral": return Color(.secondarySystemBackground)
        case "warm": return Color(red: 0.86, green: 0.62, blue: 0.22).opacity(0.18)
        case "dark": return Color(red: 0.05, green: 0.11, blue: 0.18)
        case "softMint": return Color(red: 0.34, green: 0.78, blue: 0.64).opacity(0.20)
        case "softSage": return Color(red: 0.48, green: 0.62, blue: 0.51).opacity(0.22)
        case "softTeal": return Color(red: 0.16, green: 0.62, blue: 0.58).opacity(0.18)
        case "mist": return Color(red: 0.88, green: 0.94, blue: 0.92)
        case "blush": return Color(red: 0.78, green: 0.36, blue: 0.42).opacity(0.14)
        case "softGreen": return Color.istsehGreen.opacity(0.18)
        default: return Color.istsehGreen.opacity(0.18)
        }
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
