import SwiftUI

enum BrandedLoadingStyle {
    case inline
    case card
    case fullScreen
    case compact
}

enum LoadingMessage {
    case appointments
    case medications
    case profile
    case allergies
    case conditions
    case scheduleError
    case noAppointmentsToday
    case noMedicationsDueToday
    case noAppointmentsOnDay
    case noDosesOnDay
    case custom(String, String)

    var text: String {
        let isArabic = UserDefaults.standard.string(forKey: "appearance.language") == "ar"
        switch self {
        case .appointments:
            return isArabic ? "جاري تحميل المواعيد" : "Loading appointments"
        case .medications:
            return isArabic ? "جاري تحميل الأدوية" : "Loading medications"
        case .profile:
            return isArabic ? "جاري تحميل الملف" : "Loading profile"
        case .allergies:
            return isArabic ? "جاري تحميل الحساسية" : "Loading allergies"
        case .conditions:
            return isArabic ? "جاري تحميل الحالات" : "Loading conditions"
        case .scheduleError:
            return isArabic ? "تعذر تحميل جدولك. اسحب للتحديث." : "Couldn’t load your schedule. Pull to refresh."
        case .noAppointmentsToday:
            return isArabic ? "لا توجد مواعيد اليوم." : "No appointments today."
        case .noMedicationsDueToday:
            return isArabic ? "لا توجد أدوية مستحقة اليوم." : "No medications due today."
        case .noAppointmentsOnDay:
            return isArabic ? "لا توجد مواعيد في هذا اليوم." : "No appointments on this day."
        case .noDosesOnDay:
            return isArabic ? "لا توجد جرعات في هذا اليوم." : "No doses on this day."
        case let .custom(english, arabic):
            return isArabic ? arabic : english
        }
    }
}

struct ISTSEHLoadingView: View {
    enum Style {
        case fullScreen
        case card
        case inline
        case compact
    }

    let message: String
    var style: Style = .fullScreen

    var body: some View {
        switch style {
        case .fullScreen:
            fullScreenBody
        case .card:
            cardBody
        case .inline:
            inlineBody
        case .compact:
            compactBody
        }
    }

    private var fullScreenBody: some View {
        VStack(spacing: 18) {
            loadingMark(size: 66)
            messageText(font: .system(.headline, design: .rounded).weight(.semibold), color: Color.istsehGreen)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.istsehPageBackground.ignoresSafeArea())
    }

    private var cardBody: some View {
        VStack(spacing: 14) {
            loadingMark(size: 52)
            messageText(font: .system(.subheadline, design: .rounded).weight(.semibold), color: .secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.istsehCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private var inlineBody: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color.istsehGreen)

            messageText(font: .system(.subheadline, design: .rounded), color: .secondary)
        }
        .padding(.vertical, 8)
    }

    private var compactBody: some View {
        ProgressView()
            .tint(Color.istsehGreen)
    }

    private func messageText(font: Font, color: Color) -> some View {
        Group {
            if !message.isEmpty {
                Text(message)
                    .font(font)
                    .foregroundStyle(color)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func loadingMark(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.istsehGreenSoft)
                .frame(width: size, height: size)

            Image(systemName: "pills.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(Color.istsehGreen)
        }
        .overlay(alignment: .bottomTrailing) {
            ProgressView()
                .tint(Color.istsehGreen)
                .scaleEffect(0.72)
                .padding(size * 0.02)
        }
        .accessibilityHidden(true)
    }
}

struct BrandedLoadingView: View {
    let message: String
    var style: BrandedLoadingStyle = .inline

    var body: some View {
        ISTSEHLoadingView(message: message, style: istsehStyle)
    }

    private var istsehStyle: ISTSEHLoadingView.Style {
        switch style {
        case .inline:
            return .inline
        case .card:
            return .card
        case .fullScreen:
            return .fullScreen
        case .compact:
            return .compact
        }
    }
}

struct LoadingGifView: View {
    var size: CGFloat = 120
    var message: String? = nil
    var fullScreen: Bool = false

    var body: some View {
        ISTSEHLoadingView(
            message: message ?? LoadingMessage.profile.text,
            style: fullScreen ? .fullScreen : .inline
        )
    }
}
