//
// ChatScreenCovered.swift
// StreamChatSwiftUI (Poppin fork)
//

import SwiftUI

/// A chat screen that is no pushed page gets no disappear when a page is pushed over it: the
/// app draws one in its root, beside the Chat list on the open iPhone Duo. The app says here
/// that the screen is covered, and `ChatChannelView` then rests as a covered pushed chat does
/// (`ChatChannelViewModel.onViewDissappear`: no message is taken in, so none is marked read
/// unseen) and catches up when the cover is gone (`onViewAppear`). Defaults to false, so a
/// pushed chat is left exactly as it was.
private struct ChatScreenIsCoveredKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var chatScreenIsCovered: Bool {
        get { self[ChatScreenIsCoveredKey.self] }
        set { self[ChatScreenIsCoveredKey.self] = newValue }
    }
}
