import Foundation
import AppKit

enum AppResources {
    static var bundle: Bundle? {
        // Packaged apps must not fall back to resources in the developer's build directory.
        Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/DevFlow_DevFlowApp.bundle"))
            : Bundle.module
    }
    static var logo: NSImage? {
        bundle?.url(forResource: "DevFlowLogo", withExtension: "png", subdirectory: "Resources")
            .flatMap { NSImage(contentsOf: $0) }
    }
}
