import SwiftUI

struct LandingPageView: View {
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.istsehPageBackground.ignoresSafeArea()

                VStack {
                    // Logo + Name at the top
                    VStack(spacing: 12) {
                        Image(systemName: "pills.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .foregroundStyle(Color.istsehGreen)
                        Text("ISTSEH")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(copy("Your personal medication assistant", "مساعدك الشخصي لتنظيم الأدوية"))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48)

                    Spacer()

                    // Buttons block centered
                    VStack(spacing: 20) {
                        NavigationLink(destination: SignUpPageView()) {
                            Text(copy("Sign Up", "إنشاء حساب"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(Color.istsehGreen)

                        NavigationLink(destination: LoginPageView()) {
                            Text(copy("Log In", "تسجيل الدخول"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Text(copy("── or ──", "── أو ──"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)

                        NavigationLink(destination: CareCodeEntryView()) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                Text(copy("I Have a Family Code", "لدي رمز عائلي"))
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.istsehGreen)
                    }
                    .frame(maxWidth: 340)

                    Spacer() // balances above & below to center the buttons
                }
                .padding(.horizontal, 24)

                VStack {
                    HStack {
                        Spacer()
                        languageToggle
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                    Spacer()
                }
            }
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        }
    }

    private var languageToggle: some View {
        HStack(spacing: 6) {
            languageButton(title: "EN", code: "en")
            languageButton(title: "AR", code: "ar")
        }
        .padding(4)
        .background(Color.istsehCard)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.istsehCardStroke, lineWidth: 1))
    }

    private func languageButton(title: String, code: String) -> some View {
        Button {
            languageCode = code
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(languageCode == code ? Color.istsehGreen : Color.clear)
                .foregroundStyle(languageCode == code ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(code == "ar" ? "العربية" : "English")
    }

    private func copy(_ english: String, _ arabic: String) -> String {
        isArabic ? arabic : english
    }
}
