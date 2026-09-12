import SwiftUI

enum ProteinTheme {
    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let extraLarge: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 24
        static let button: CGFloat = 16
    }

    enum Color {
        static let accent = SwiftUI.Color.green
        static let surface = SwiftUI.Color(.secondarySystemBackground)
        static let subduedText = SwiftUI.Color.secondary
    }
}

struct ProteinCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ProteinTheme.Spacing.large)
            .background(ProteinTheme.Color.surface, in: RoundedRectangle(cornerRadius: ProteinTheme.Radius.card))
    }
}

struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ProteinTheme.Spacing.medium)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: ProteinTheme.Radius.button))
        .tint(ProteinTheme.Color.accent)
    }
}
