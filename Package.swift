// swift-tools-version:5.5
// When used via SPM the minimum Swift version is 5.3 because we need support for resources

import Foundation
import PackageDescription

let package = Package(
    name: "StreamChatSwiftUI",
    defaultLocalization: "en",
    platforms: [
      .iOS(.v14), .macOS(.v11)
    ],
    products: [
        .library(
            name: "StreamChatSwiftUI",
            targets: ["StreamChatSwiftUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/GetStream/stream-chat-swift.git", from: "4.52.0"),
        .package(url: "https://github.com/kean/Nuke.git", .exact("11.3.1")),
        .package(url: "https://github.com/Flowductive/shiny-swift-ui.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "StreamChatSwiftUI",
            dependencies: [.product(name: "StreamChat", package: "stream-chat-swift")],
            exclude: ["README.md", "Info.plist", "Generated/L10n_template.stencil"],
            resources: [.process("Resources")]
        )
    ]
)

#if swift(>=5.6)
package.dependencies.append(
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")
)
#endif
