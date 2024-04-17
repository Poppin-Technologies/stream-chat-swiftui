//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

public struct TrailingComposerView: View {
    
    @Injected(\.utils) private var utils
        
    @EnvironmentObject var viewModel: MessageComposerViewModel
    var onTap: () -> Void
    
    public init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }
    
    public var body: some View {
        Group {
            if viewModel.cooldownDuration == 0 {
                HStack(spacing: 16) {
                    SendMessageButton(
                        enabled: viewModel.sendButtonEnabled,
                        onTap: onTap
                    )
                    if utils.composerConfig.isVoiceRecordingEnabled {
                        VoiceRecordingButton(viewModel: viewModel)
                    }
                }
                .padding(.bottom, 8)
            } else {
                SlowModeView(
                    cooldownDuration: viewModel.cooldownDuration
                )
            }
        }
    }
}

public struct VoiceRecordingButton: View {
    @Injected(\.colors) var colors
    @Injected(\.utils) var utils
    
    @ObservedObject public var viewModel: MessageComposerViewModel
    
    @State private var longPressed = false
    @State private var longPressStarted: Date?

    public init(viewModel: MessageComposerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Image(systemName: "mic")
            .foregroundColor(Color(colors.textLowEmphasis))
            .padding(3)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        viewModel.dragStarted = true
                        viewModel.dragLocation = value.location
                        if value.location.y < -60 && viewModel.recordingState == .initial {
                          withAnimation(.spring(response: 0.3, dampingFraction: 1.2)) {
                            startRecording(location: value.location)
                            viewModel.recordingState = .locked
                          }
                        }
                        if !longPressed {
                          longPressStarted = Date()
                          longPressed = true
                          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            if longPressed {
                              withAnimation(.spring(response: 0.3, dampingFraction: 1.2)) {
                                startRecording(location: value.location)
                              }
                            }
                          }
                        } else if case .recording = viewModel.recordingState {
                            viewModel.recordingState = .recording(value.location)
                        }
                    }
                    .onEnded { _ in
                        longPressed = false
                        viewModel.dragStarted = false
                      if let longPressStarted, Date().timeIntervalSince(longPressStarted) <= 0.5 {
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.warning)
                            if viewModel.recordingState != .showingTip {
                                viewModel.recordingState = .showingTip
                            }
                            self.longPressStarted = nil
                            return
                        }
                        if viewModel.recordingState != .locked {
                            viewModel.stopRecording()
                        }
                    }
            )
            .if(true) { view in
              Group {
                if #available(iOS 16.0, *) {
                  view
                    .defersSystemGestures(on: .all)
                } else {
                  view
                }
              }
            }
    }
  
  func startRecording(location: CGPoint)
  {
    triggerHapticFeedback(style: .soft)
    viewModel.recordingState = .recording(location)
    viewModel.startRecording()
  }
}
