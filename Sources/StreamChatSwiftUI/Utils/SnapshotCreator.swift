//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import SwiftUI

/// Helper for creating snapshot from SwiftUI Views.
public protocol SnapshotCreator {

    /// Creates a snapshot of the provided SwiftUI view.
    ///  - Parameter view: the view whose snapshot would be created.
    ///  - Returns: `UIImage` representing the snapshot of the view.
    func makeSnapshot(for view: AnyView) -> UIImage
}

/// Default implementation of the `SnapshotCreator`.
public class DefaultSnapshotCreator: SnapshotCreator {

    @Injected(\.images) var images

    public init() { /* Public init. */ }

    public func makeSnapshot(for view: AnyView) -> UIImage {
        guard let uiView: UIView = topVC()?.view else {
            return images.snapshot
        }
        return makeSnapshot(from: uiView)
    }

    func makeSnapshot(from view: UIView) -> UIImage {
        let currentSnapshot: UIImage?
        UIGraphicsBeginImageContext(view.frame.size)
        if let currentGraphicsContext = UIGraphicsGetCurrentContext() {
            // Poppin: the screen as it is drawn, blurs and glass included. `layer.render`
            // draws the layers without their filters: behind the reply view (which blurs
            // the conversation) the hold menu's backdrop showed the conversation sharp, on
            // top of the thread. It stays as the fallback for a view that cannot be drawn.
            if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
                view.layer.render(in: currentGraphicsContext)
            }
            currentSnapshot = UIGraphicsGetImageFromCurrentImageContext()
        } else {
            currentSnapshot = images.snapshot
        }
        UIGraphicsEndImageContext()
        return currentSnapshot ?? images.snapshot
    }
}
