import SwiftUI

enum ISTSEHLayout {
    static var isArabic: Bool {
        if let stored = UserDefaults.standard.string(forKey: "appearance.language"), !stored.isEmpty {
            return stored == "ar"
        }
        return Locale.current.language.languageCode?.identifier == "ar"
    }

    static var direction: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }
    static var textAlignment: TextAlignment { isArabic ? .trailing : .leading }
    static var horizontalAlignment: HorizontalAlignment { isArabic ? .trailing : .leading }
    static var frameAlignment: Alignment { isArabic ? .trailing : .leading }
}

struct ISTSEHPageBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.istsehMintBackground,
                Color.istsehMintBackground,
                Color.istsehGreen.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct ISTSEHPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if ISTSEHLayout.isArabic { trailing }
            VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 5) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(ISTSEHLayout.textAlignment)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(ISTSEHLayout.textAlignment)
                }
            }
            Spacer()
            if !ISTSEHLayout.isArabic { trailing }
        }
        .padding(.horizontal, ISTSEHSpacing.pageHorizontal)
        .padding(.top, 12)
    }
}

extension ISTSEHPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

struct ISTSEHCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 14) {
            content
        }
        .padding(ISTSEHSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: ISTSEHLayout.frameAlignment)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : Color.istsehGreen.opacity(0.08),
            radius: 18,
            x: 0,
            y: 10
        )
    }
}

struct ISTSEHPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(isDisabled ? Color.secondary.opacity(0.35) : Color.istsehGreen)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityAddTraits(.isButton)
    }
}

struct ISTSEHSecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(Color.istsehGreen)
            .background(Color.istsehGreenSoft)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ISTSEHIconBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let systemName: String
    var color: Color = .istsehGreen

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 42, height: 42)
            .background(color.opacity(colorScheme == .dark ? 0.16 : 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(color.opacity(colorScheme == .dark ? 0.18 : 0.0), lineWidth: 1)
            )
    }
}

struct ISTSEHStatusPill: View {
    let title: String
    var systemImage: String?
    var color: Color = .istsehGreen

    var body: some View {
        Label {
            Text(title)
                .font(.footnote.weight(.semibold))
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(color)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}

struct ISTSEHEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ISTSEHCard {
            VStack(spacing: 14) {
                ISTSEHIconBadge(systemName: systemImage)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let buttonTitle, let action {
                    ISTSEHPrimaryButton(title: buttonTitle, action: action)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ISTSEHInlineEmptyState: View {
    let systemImage: String
    let title: String
    var message: String?

    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                ISTSEHIconBadge(systemName: systemImage)
                    .scaleEffect(1.08)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.vertical, 14)
            Spacer()
        }
    }
}

struct ISTSEHMedicationCard: View {
    let name: String
    let subtitle: String
    let detail: String
    var warningCount: Int = 0
    var isAsNeeded = false
    var isManual = false
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            ISTSEHCard {
                HStack(alignment: .top, spacing: 14) {
                    if !ISTSEHLayout.isArabic { ISTSEHIconBadge(systemName: "pills.fill") }
                    VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 8) {
                        Text(name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(ISTSEHLayout.textAlignment)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(ISTSEHLayout.textAlignment)
                        Text(detail)
                            .font(.headline)
                            .foregroundStyle(Color.istsehGreen)
                            .multilineTextAlignment(ISTSEHLayout.textAlignment)
                        HStack(spacing: 8) {
                            if warningCount > 0 {
                                ISTSEHStatusPill(title: "\(warningCount) warning", systemImage: "exclamationmark.triangle.fill", color: .istsehWarning)
                            }
                            if isAsNeeded {
                                ISTSEHStatusPill(title: "As needed", systemImage: "hand.raised.fill", color: .secondary)
                            }
                            ISTSEHStatusPill(title: isManual ? "Manual" : "Auto", systemImage: isManual ? "slider.horizontal.3" : "sparkles", color: isManual ? .secondary : .istsehGreen)
                        }
                    }
                    Spacer()
                    if ISTSEHLayout.isArabic { ISTSEHIconBadge(systemName: "pills.fill") }
                    Image(systemName: ISTSEHLayout.isArabic ? "chevron.left" : "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ISTSEHFormField<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(ISTSEHLayout.textAlignment)
            content
                .frame(minHeight: 48)
                .padding(.horizontal, 12)
                .background(Color.istsehCard)
                .clipShape(RoundedRectangle(cornerRadius: ISTSEHSpacing.controlRadius, style: .continuous))
        }
    }
}

struct ISTSEHSegmentOption: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 92, height: 82)
        .foregroundStyle(isSelected ? Color.white : Color.istsehGreen)
        .background(isSelected ? Color.istsehGreen : Color.istsehGreenSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct ISTSEHWarningBanner: View {
    let title: String
    let message: String
    var color: Color
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
