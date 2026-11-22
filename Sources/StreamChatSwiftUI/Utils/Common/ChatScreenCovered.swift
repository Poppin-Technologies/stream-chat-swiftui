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

/// Poppin: the ground of the chat screen that the app covers with something of its own while
/// the chat stands in one part of the window: its tab bar under the chat and the status column
/// beside it, where the chat stands beside the Chat list on the open iPhone Duo. A held
/// message's menu keeps clear of it (`ReactionsOverlayView`). Zero wherever the chat is the
/// whole window, so nothing moves on any other screen.
private struct ChatHoldMenuCoverKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

public extension EnvironmentValues {
    var chatHoldMenuCover: EdgeInsets {
        get { self[ChatHoldMenuCoverKey.self] }
        set { self[ChatHoldMenuCoverKey.self] = newValue }
    }
}
