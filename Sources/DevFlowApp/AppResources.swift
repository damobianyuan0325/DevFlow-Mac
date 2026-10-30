import Foundation
import AppKit

enum AppResources {
    static var releaseVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "DevFlowReleaseVersion") as? String ?? "源码运行版"
    }
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
