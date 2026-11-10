//
// NewestMessageRow.swift
// StreamChatSwiftUI (Poppin fork)
//

import SwiftUI

/// Whether a message row is the conversation's newest bubble (system and error lines do not
/// count). `MessageListView` sets it on every row; `MessageContainerView` reads it to draw the
/// read indicator only under that row (when it is the current user's), the way Messages shows
/// "Delivered". Defaults to true for a container built outside the list.
private struct IsNewestMessageRowKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

public extension EnvironmentValues {
    var isNewestMessageRow: Bool {
        get { self[IsNewestMessageRowKey.self] }
        set { self[IsNewestMessageRowKey.self] = newValue }
    }
}
