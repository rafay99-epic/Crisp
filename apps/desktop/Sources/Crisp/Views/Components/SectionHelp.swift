import SwiftUI

/// A quiet "?" button for a Settings section header. The header stays a one-line
/// label; the full "how it works" explanation lives one click away in a popover —
/// the macOS System Settings pattern. Keeps every option's detail without a wall
/// of gray prose under each control (one system, not two: every section uses this).
///
/// Use it in a Section `header:` beside the title, and drop the old evergreen
/// `footer:` — the text it held moves into `text` here.
struct SectionHelp: View {
    let text: LocalizedStringKey
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("What\u{2019}s this?")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(16)
        }
    }
}

/// A section header that pairs a title with its `SectionHelp` popover, so the
/// title/`(?)` layout is defined once instead of copied into every Section.
struct SettingsSectionHeader: View {
    let title: String
    let help: LocalizedStringKey

    init(_ title: String, help: LocalizedStringKey) {
        self.title = title
        self.help = help
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            SectionHelp(text: help)
        }
    }
}
