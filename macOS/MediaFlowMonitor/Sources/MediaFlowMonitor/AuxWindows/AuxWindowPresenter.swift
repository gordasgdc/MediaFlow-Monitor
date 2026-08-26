import AppKit
import SwiftUI

/// Prezintă ferestre native auxiliare (Help/About) hostuind conținut
/// SwiftUI — separate de overlay-ul principal (`OverlayWindowController`),
/// ca userul să poată avea Dashboard-ul deschis ȘI ghidul/About în același timp.
enum AuxWindowPresenter {
    private static var controllers: [String: NSWindowController] = [:]

    static func present<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let existing = controllers[id], let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: content())

        let controller = NSWindowController(window: window)
        controllers[id] = controller

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            controllers[id] = nil
        }

        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
