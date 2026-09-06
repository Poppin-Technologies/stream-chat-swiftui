//
// MessageListTopInset.swift
// StreamChatSwiftUI (Poppin fork)
//

import SwiftUI

/// The space `MessageListView` reserves above its newest-at-bottom content so the first
/// visible row clears a header that floats over the list (`ChatChannelView` stacks the header
/// at zIndex 99 under `edgesIgnoringSafeArea(.top)`). Defaults to the historical 110pt — a
/// 59pt safe-area top plus a 51pt pill header — so every consumer keeps its layout; the app
/// injects `safeAreaInsets.top + <its header's content height>` where it knows both.
private struct MessageListTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 110
}

public extension EnvironmentValues {
    var messageListTopInset: CGFloat {
        get { self[MessageListTopInsetKey.self] }
        set { self[MessageListTopInsetKey.self] = newValue }
    }
}
