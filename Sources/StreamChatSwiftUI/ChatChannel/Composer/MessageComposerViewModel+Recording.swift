//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import StreamChat
import SwiftUI

public struct AudioRecordingInfo: Equatable {
    /// The waveform of the recording.
    public var waveform: [Float]
    /// The duration of the recording.
    public var duration: TimeInterval
    
    mutating func update(with entry: Float, duration: TimeInterval) {
        waveform.append(entry)
        self.duration = duration
    }
}

extension AudioRecordingInfo {
    static let initial = AudioRecordingInfo(waveform: [], duration: 0)
}

extension MessageComposerViewModel: AudioRecordingDelegate {
    public func audioRecorder(
        _ audioRecorder: AudioRecording,
        didUpdateContext: AudioRecordingContext
    ) {
        audioRecordingInfo.update(
            with: didUpdateContext.averagePower,
            duration: didUpdateContext.duration
        )
    }
    
    public func audioRecorder(
        _ audioRecorder: AudioRecording,
        didFinishRecordingAtURL location: URL
    ) {
        if audioRecordingInfo == .initial {
            // Discarded before anything was kept (the trash button mid-record, a tap shorter than
            // the engine's first metering beat): the file goes too, nothing lingers in tmp.
            try? FileManager.default.removeItem(at: location)
            return
        }
        audioAnalysisFactory?.waveformVisualisation(
            fromAudioURL: location,
            for: waveformTargetSamples,
            completionHandler: { [weak self] result in
                guard let self else { return }
                switch result {
                case let .success(waveform):
                    DispatchQueue.main.async {
                        let recording = AddedVoiceRecording(
                            url: location,
                            duration: self.audioRecordingInfo.duration,
                            waveform: waveform
                        )
                        if self.recordingState == .stopped || self.utils.composerConfig.voiceRecordingReviewsBeforeSend {
                            // Poppin: a finished take always lands in the review bar, even when the
                            // engine stopped it (a call, the 5 min cap) before the user did.
                            self.pendingAudioRecording = recording
                            self.audioRecordingInfo.waveform = waveform
                            self.recordingState = .stopped
                        } else {
                            self.addedVoiceRecordings.append(recording)
                            self.recordingState = .initial
                            self.audioRecordingInfo = .initial
                        }
                    }
                case let .failure(error):
                    log.error(error)
                    // Unreadable take: nothing to review, nothing to keep.
                    try? FileManager.default.removeItem(at: location)
                    self.recordingState = .initial
                    self.audioRecordingInfo = .initial
                }
            }
        )
    }
    
    public func audioRecorder(
        _ audioRecorder: AudioRecording,
        didFailWithError error: Error
    ) {
        log.error(error)
        recordingState = .initial
        audioRecordingInfo = .initial
    }
}

extension MessageComposerViewModel {
    public func startRecording() {
        utils.audioSessionFeedbackGenerator.feedbackForBeginRecording()
        audioRecorder.beginRecording {
            log.debug("started recording")
        }
    }
    
    public func stopRecording() {
        utils.audioSessionFeedbackGenerator.feedbackForStopRecording()
        audioRecorder.stopRecording()
    }
    
    public func resumeRecording() {
        utils.audioSessionFeedbackGenerator.feedbackForBeginRecording()
        audioRecorder.resumeRecording()
    }
    
    public func pauseRecording() {
        utils.audioSessionFeedbackGenerator.feedbackForPause()
        audioRecorder.pauseRecording()
    }
}

extension MessageComposerViewModel {
    public func discardRecording() {
        // Poppin: a reviewed note that is thrown away leaves no file behind (the stock path kept
        // the pending recording and its tmp file; a fast stop → send could ship a discarded take).
        if let pending = pendingAudioRecording {
            try? FileManager.default.removeItem(at: pending.url)
        }
        pendingAudioRecording = nil
        pendingVoiceTranscript = nil
        recordingState = .initial
        audioRecordingInfo = .initial
        stopRecording()
    }

    /// Poppin's review bar sends the stopped note as its own message: the pending recording moves
    /// into `voiceRecordingToSend` (never into `addedVoiceRecordings`, so the stock chip never
    /// renders), the recording UI resets, and `voiceSendRequestCount` bumps - `MessageComposerView`
    /// observes it and runs its send closure. A no-op without a pending recording.
    public func requestVoiceSend() {
        guard let pending = pendingAudioRecording else { return }
        voiceRecordingToSend = (pending, pendingVoiceTranscript)
        pendingAudioRecording = nil
        pendingVoiceTranscript = nil
        audioRecordingInfo = .initial
        recordingState = .initial
        voiceSendRequestCount += 1
    }
    
    public func confirmRecording() {
        if recordingState == .stopped {
            if let pending = pendingAudioRecording {
                addedVoiceRecordings.append(pending)
                pendingAudioRecording = nil
                audioRecordingInfo = .initial
                recordingState = .initial
            }
        } else {
            stopRecording()
        }
    }
    
    public func previewRecording() {
        recordingState = .stopped
        stopRecording()
    }
}
