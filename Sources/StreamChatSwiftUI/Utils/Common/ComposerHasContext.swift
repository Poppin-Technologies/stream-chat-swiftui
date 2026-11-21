//
// ComposerHasContext.swift
// StreamChatSwiftUI (Poppin fork)
//

import SwiftUI

/// True while the composer writes a reply (a quoted message) or an edit of a sent message.
/// The composer sets it on its field row, so the app's own views in that row (the "+" menu,
/// the send button) can offer what belongs to a plain new message only: Send Later. Both
/// messages live in the composer view as bindings and reach no factory slot of the row.
/// Defaults to false.
private struct ComposerHasContextKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var composerHasContext: Bool {
        get { self[ComposerHasContextKey.self] }
        set { self[ComposerHasContextKey.self] = newValue }
    }
}
