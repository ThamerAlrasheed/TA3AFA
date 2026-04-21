import SwiftUI

// MARK: - Small reusable views
struct InfoSection: View {
    let title: String
    let bullets: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
                .tracking(1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets.prefix(4), id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(.systemGreen))
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
        FlexibleWrap(items: items) { text in
            Text(text)
                .font(.footnote)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
    }
}

struct FlexibleWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content
    @State private var totalHeight = CGFloat.zero

    var body: some View {
        VStack { GeometryReader { geo in self.generateContent(in: geo) } }
            .frame(height: totalHeight)
    }

    private func generateContent(in g: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: .topLeading) {
            ForEach(items, id: \.self) { item in
                content(item)
                    .alignmentGuide(.leading) { d in
                        if (abs(width - d.width) > g.size.width) { width = 0; height -= d.height }
                        let result = width
                        if item == items.last! { width = 0 } else { width -= d.width }
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
