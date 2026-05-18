import SwiftUI
import SDWebImageSwiftUI

enum BrandedLoadingStyle {
    case inline
    case card
    case fullScreen
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
            return isArabic ? "جاري تحميل المواعيد…" : "Loading appointments…"
        case .medications:
            return isArabic ? "جاري تحميل الأدوية…" : "Loading medications…"
        case .profile:
            return isArabic ? "جاري تحميل الملف الطبي…" : "Loading profile…"
        case .allergies:
            return isArabic ? "جاري تحميل الحساسية…" : "Loading allergies…"
        case .conditions:
            return isArabic ? "جاري تحميل الأمراض المزمنة…" : "Loading conditions…"
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

struct BrandedLoadingView: View {
    let message: String
    var style: BrandedLoadingStyle = .inline
    @Environment(\.colorScheme) private var colorScheme

    private var imageSize: CGFloat {
        switch style {
        case .inline, .card: return 92
        case .fullScreen: return 132
        }
    }

    private var verticalPadding: CGFloat {
        switch style {
        case .inline: return 12
        case .card: return 22
        case .fullScreen: return 0
        }
    }

    var body: some View {
        Group {
            switch style {
            case .fullScreen:
                ZStack {
                    Color.istsehPageBackground.ignoresSafeArea()
                    content
                }
            case .card:
                content
                    .padding(22)
                    .frame(maxWidth: .infinity)
                    .background(Color.istsehCard)
                    .clipShape(RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous)
                            .stroke(Color.istsehCardStroke, lineWidth: 1)
                    )
            case .inline:
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            loaderArtwork
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.istsehGreen)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, verticalPadding)
    }

    private var loaderArtwork: some View {
        ZStack {
            AnimatedImage(name: "loading_gif.gif")
                .resizable()
                .scaledToFit()
                .frame(width: imageSize * 1.42, height: imageSize * 0.92)
                .compositingGroup()
                .blendMode(colorScheme == .dark ? .screen : .normal)
        }
        .frame(width: imageSize * 1.48, height: imageSize)
        .accessibilityHidden(true)
    }
}

struct LoadingGifView: View {
    var size: CGFloat = 120
    var message: String? = nil
    var fullScreen: Bool = false

    var body: some View {
        BrandedLoadingView(
            message: message ?? LoadingMessage.profile.text,
            style: fullScreen ? .fullScreen : .inline
        ) 
    }
}
