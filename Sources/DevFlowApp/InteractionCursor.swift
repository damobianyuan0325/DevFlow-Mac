import SwiftUI
import AppKit

/// Preserve native button rendering, keyboard activation and disabled semantics.
struct HandButtonStyle<Base: PrimitiveButtonStyle>: PrimitiveButtonStyle {
    let base: Base
    func makeBody(configuration: Configuration) -> some View {
        base.makeBody(configuration: configuration).handCursor()
            .accessibilityRepresentation {
                Button(action: configuration.trigger) { configuration.label }
                    .buttonStyle(base)
            }
    }
}

extension View {
    func handCursor() -> some View { modifier(HandCursorModifier()) }
}

private struct HandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.background(CursorRegion(enabled: enabled).accessibilityHidden(true))
    }
}

private struct CursorRegion: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> CursorRegionView {
        let view = CursorRegionView()
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: CursorRegionView, context: Context) {
        view.enabled = enabled
        view.window?.invalidateCursorRects(for: view)
    }
}

/// AppKit owns enter/exit and removal of the region; no global push/pop stack.
private final class CursorRegionView: NSView {
    var enabled = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func resetCursorRects() {
        super.resetCursorRects()
        if enabled { addCursorRect(bounds, cursor: .pointingHand) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
    override func setFrameSize(_ size: NSSize) {
        super.setFrameSize(size)
        window?.invalidateCursorRects(for: self)
    }
}
