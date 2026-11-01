import SwiftUI

struct WindowRootView: View {
    @ObservedObject var session: BrowserSession
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Group {
            if session.isSplitView, let secondary = session.secondary {
                HStack(spacing: 0) {
                    SplitPaneHost(session: session, pane: session.primary, side: .primary)
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                    SplitPaneHost(session: session, pane: secondary, side: .secondary)
                }
            } else {
                RootView(model: session.primary.model, tabs: session.primary.tabs)
            }
        }
    }
}

private struct SplitPaneHost: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var model: ExplorerModel
    @ObservedObject var tabs: TabManager
    let side: BrowserPaneSide

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    init(session: BrowserSession, pane: BrowserPane, side: BrowserPaneSide) {
        self.session = session
        self.side = side
        self._model = ObservedObject(wrappedValue: pane.model)
        self._tabs = ObservedObject(wrappedValue: pane.tabs)
    }

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }
    private var isActive: Bool { session.activeSide == side }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? theme.accent : theme.contentSecondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.toolbarSecondary)
                Text(model.currentFolderName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.toolbarText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isActive {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .tracking(0.6)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(isActive ? theme.field : theme.toolbar)
            .contentShape(Rectangle())
            .onTapGesture { session.activate(side) }
            .help("Click to make this pane active")

            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)

            RootView(model: model, tabs: tabs)
        }
        .background(theme.background)
        .overlay(
            Rectangle()
                .strokeBorder(isActive ? theme.accent.opacity(0.7) : Color.clear, lineWidth: 2)
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                session.activate(side)
            }
        )
    }
}
