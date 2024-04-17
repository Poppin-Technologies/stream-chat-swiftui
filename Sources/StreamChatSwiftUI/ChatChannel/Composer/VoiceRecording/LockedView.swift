//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI
import ShinySwiftUI

struct LockedView: View {
    @Injected(\.colors) var colors
    @Injected(\.utils) var utils
    
    @ObservedObject var viewModel: MessageComposerViewModel
    @State var isPlaying = false
    @State var showLockedIndicator = true
    @State var slideToCancelOffset: CGFloat = 0.0
    @State var isLocked: Bool = false
    @State var showingLockAnimation = false
    @StateObject var voiceRecordingHandler = VoiceRecordingHandler()
    var namespace: Namespace.ID

    private let initialLockOffset: CGFloat = -70
    private let maxLockOffset: CGFloat = -110
    private var player: AudioPlaying {
        utils.audioPlayer
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Divider()
            HStack {
              if viewModel.recordingState == .stopped {
                Button {
                  handlePlayTap()
                } label: {
                  Image(systemName: isPlaying ? "pause" : "play")
                    .foregroundColor(colors.tintColor)
                }
              } else {
                Image(systemName: "mic")
                  .foregroundColor(.red)
              }
              if viewModel.recordingState != .locked && viewModel.recordingState != .stopped {

                RecordingDurationView(duration: showContextTime ?
                                      voiceRecordingHandler.context.currentTime : viewModel.audioRecordingInfo.duration)
                .matchedGeometryEffect(id: "Recording", in: namespace)
                Spacer()
                HStack {
                  Text(L10n.Composer.Recording.slideToCancel)
                  Image(systemName: "chevron.left")
                }
                .foregroundColor(Color(colors.textLowEmphasis))
                .transition(.opacity.animation(.easeInOut))
                .offset(x: slideToCancelOffset)
                .after(0.2) {
                  withAnimation(.interpolatingSpring(mass: 1.5, stiffness: 170, damping: 25).repeatForever(autoreverses: true)) {
                    slideToCancelOffset = -5
                  }
                }
                
                Spacer()
              }
              if viewModel.recordingState == .locked || viewModel.recordingState == .stopped {
                RecordingDurationView(
                  duration: showContextTime ?
                  voiceRecordingHandler.context.currentTime : viewModel.audioRecordingInfo.duration
                )
                .matchedGeometryEffect(id: "Recording", in: namespace)
                RecordingWaveform(
                  duration: viewModel.audioRecordingInfo.duration,
                  currentTime: viewModel.recordingState == .stopped ?
                  voiceRecordingHandler.context.currentTime :
                    viewModel.audioRecordingInfo.duration,
                  waveform: viewModel.audioRecordingInfo.waveform
                )
              }
              Spacer()
            }
            .padding(.horizontal, 8)
            .opacity(opacityForSlideToCancel)

          if viewModel.recordingState == .locked || viewModel.recordingState == .stopped {
            HStack {
              Button {
                withAnimation {
                  viewModel.discardRecording()
                }
              } label: {
                Image(systemName: "trash")
                  .foregroundColor(colors.tintColor)
              }
              
              Spacer()
              
              Button {
                withAnimation {
                  viewModel.previewRecording()
                }
              } label: {
                Image(systemName: "stop.circle")
                  .foregroundColor(.red)
              }
              
              Spacer()
              
              Button {
                withAnimation {
                  viewModel.confirmRecording()
                }
              } label: {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(colors.tintColor)
              }
            }
            .padding(.horizontal, 8)
          }
        }
        .background(Color(colors.background).edgesIgnoringSafeArea(.bottom))
        .offset(y: -20)
        .background(Color(colors.background).edgesIgnoringSafeArea(.bottom))
        .overlay(
            TopRightView {
              Group {
                if viewModel.recordingState != .locked {
                  LockView()
                    .padding(.all, 4)
                    .offset(y: lockViewOffset)
                    .animation(.interpolatingSpring(stiffness: 170, damping: 25), value: showingLockAnimation)
                    .transition(.opacity.animation(.easeInOut(duration: 0.8)))
                }
              }
            }
        )
        .onAppear {
            player.subscribe(voiceRecordingHandler)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showLockedIndicator = false
            }
        }
        .onReceive(voiceRecordingHandler.$context, perform: { value in
            if value.state == .stopped || value.state == .paused {
                isPlaying = false
            } else if value.state == .playing {
                isPlaying = true
              
              
            }
        })
    }
    
    private var loc: CGPoint {
      viewModel.dragLocation
    }
  
    private var showContextTime: Bool {
        voiceRecordingHandler.context.currentTime > 0
    }
  
    private var lockViewOffset: CGFloat {
        if viewModel.dragLocation.y > 0 {
            return initialLockOffset
        }
      let o = initialLockOffset + viewModel.dragLocation.y
      if o >= maxLockOffset {
        showingLockAnimation = true
      }
      return max(maxLockOffset, o)
    }
  
    private var opacityForSlideToCancel: CGFloat {
        guard loc.x < RecordingConstants.cancelMinDistance else { return 1 }
        let opacity = (1 - loc.x / RecordingConstants.cancelMaxDistance)
        return opacity
    }
    
    private func handlePlayTap() {
        if isPlaying {
            player.pause()
        } else if let url = viewModel.pendingAudioRecording?.url {
            player.loadAsset(from: url)
        }
        isPlaying.toggle()
    }
}

struct LockedRecordIndicator: View {
    @Injected(\.colors) var colors
    
    var body: some View {
        Image(systemName: "lock")
            .padding(.all, 8)
            .background(Color(colors.background6))
            .foregroundColor(.blue)
            .clipShape(Circle())
            .offset(y: -66)
            .padding(.all, 4)
    }
}
