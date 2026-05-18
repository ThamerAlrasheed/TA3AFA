import SwiftUI

enum AppColors {
    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x2E / 255.0, alpha: 1.0)
            : UIColor(red: 0.93, green: 0.98, blue: 0.95, alpha: 1.0)
    })

    static let appCard = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x3A / 255.0, alpha: 1.0)
            : UIColor.white
    })

    static let appCardStroke = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.06)
    })

    static let appGreen = Color(red: 0x2E / 255.0, green: 0xCC / 255.0, blue: 0x71 / 255.0)
    static let appGreenDark = Color(red: 0x2C / 255.0, green: 0xA8 / 255.0, blue: 0x61 / 255.0)
    static let appMutedText = Color.secondary
    static let appPrimaryText = Color.primary
}

extension Color {
    static let istsehPageBackground = AppColors.appBackground
    static let istsehMintBackground = AppColors.appBackground
    static let istsehCard = AppColors.appCard
    static let istsehCardStroke = AppColors.appCardStroke
    static let istsehGreen = AppColors.appGreen
    static let istsehGreenDark = AppColors.appGreenDark
    static let istsehBrightGreen = AppColors.appGreen
    static let istsehGreenSoft = Color.istsehGreen.opacity(0.14)

    static let istsehTextPrimary = AppColors.appPrimaryText
    static let istsehTextSecondary = AppColors.appMutedText
    static let istsehWarning = Color.orange
    static let istsehDanger = Color.red
}

enum ISTSEHSpacing {
    static let pageHorizontal: CGFloat = 20
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 17
}
