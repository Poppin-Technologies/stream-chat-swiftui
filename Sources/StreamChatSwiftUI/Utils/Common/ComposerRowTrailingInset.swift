//
// ComposerRowTrailingInset.swift
// StreamChatSwiftUI (Poppin fork)
//

import SwiftUI

/// Extra room on the trailing side of the composer's field row only (the leading view and the
/// input field), on top of the row's own 8pt. The app sets it from its composer view modifier
/// so the field's right edge can sit on the screen's side margin while everything else in the
/// composer (the attachment picker, the recording bar, the reply header) keeps its own
/// insets. Defaults to 0.
private struct ComposerRowTrailingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
    var composerRowTrailingInset: CGFloat {
        get { self[ComposerRowTrailingInsetKey.self] }
        set { self[ComposerRowTrailingInsetKey.self] = newValue }
    }
}

/// Reads the inset where the row sits in the tree: the composer's own `@Environment` would
/// see the value from outside the modifier that sets it.
struct ComposerRowTrailingInsetModifier: ViewModifier {
    @Environment(\.composerRowTrailingInset) private var inset

    func body(content: Content) -> some View {
        content.padding(.trailing, inset)
    }
}
