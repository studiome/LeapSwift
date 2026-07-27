//
//  MockBundle.swift
//  LeapSwift
//

import Foundation

// Where the bundled MockData JSON files live depends on how LeapSwift was
// built: Swift Package Manager generates a synthetic resource bundle
// (`Bundle.module`), while the Xcode framework target embeds resources
// directly in the framework bundle, found via any class defined in it.
extension Bundle {
    static var leapSwiftResources: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        Bundle(for: BundleToken.self)
        #endif
    }
}

private final class BundleToken {}
