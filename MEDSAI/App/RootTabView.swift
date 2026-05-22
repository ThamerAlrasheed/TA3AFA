import SwiftUI

struct RootTabView: View {
    // Read shared objects injected in MediScheduleApp (do not inject here)
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var medsRepo: UserMedsRepo

    // 0 Today, 1 Schedule, 2 Meds, 3 Search, 4 Settings
    @State private var selection: Int = 1
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                appBackground
                    .ignoresSafeArea()

                // Real TabView for navigation/state; the stock bar is fully hidden.
                TabView(selection: $selection) {
                    TodayScheduleView().tag(0)
                    SchedulePageView().tag(1)
                    MedListView().tag(2)
                    SearchView().tag(3)
                    SettingsView().tag(4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .bottom)
                .toolbar(.hidden, for: .tabBar)
                .onAppear {
                    UITabBar.appearance().isHidden = true
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    GlassTabBar(selection: $selection) { nextSelection in
                        selectTab(nextSelection)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, tabBarDockPadding(proxy))
                }
                .ignoresSafeArea(.keyboard)
                .ignoresSafeArea(edges: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func tabBarDockPadding(_ proxy: GeometryProxy) -> CGFloat {
        4
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [
                Color.istsehMintBackground.opacity(0.55),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func selectTab(_ nextSelection: Int) {
        guard nextSelection != selection else { return }

        withAnimation(.easeInOut(duration: 0.18)) {
            selection = nextSelection
        }
    }
}

// MARK: - Glass Tab Bar

private struct GlassTabBar: View {
    @Binding var selection: Int
    let onSelect: (Int) -> Void
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private struct Item: Identifiable {
        let id: Int
        let title: String
        let systemImage: String
    }

    // Order must match the TabView tags above
    private var items: [Item] {
        [
            .init(id: 0, title: localized("Today", "اليوم"), systemImage: "calendar.badge.clock"),
            .init(id: 1, title: localized("Schedule", "الجدول"), systemImage: "calendar"),
            .init(id: 2, title: localized("Meds", "الأدوية"), systemImage: "pills.fill"),
            .init(id: 3, title: localized("Search", "البحث"), systemImage: "magnifyingglass"),
            .init(id: 4, title: localized("Settings", "الإعدادات"), systemImage: "gearshape")
        ]
    }

    private func localized(_ english: String, _ arabic: String) -> String {
        languageCode == "ar" ? arabic : english
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                GlassTabButton(
                    isSelected: selection == item.id,
                    title: item.title,
                    systemImage: item.systemImage
                ) {
                    onSelect(item.id)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .frame(maxWidth: .infinity) // equal width per tab
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10) // a bit taller to fit icon+label
        .background(.ultraThinMaterial) // iOS glass/frosted effect
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 2,  x: 0, y: 1)
    }
}

private struct GlassTabButton: View {
    let isSelected: Bool
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) { // icon on top, text underneath (prevents truncation)
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85) // prefer slight shrink over ellipses
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isSelected ? 0.35 : 0.18),
                                lineWidth: isSelected ? 0.8 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
