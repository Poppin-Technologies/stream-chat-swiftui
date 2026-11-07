//
// Copyright © 2024 Stream.io Inc. All rights reserved.
//

import ImageIO
import Photos
import StreamChat
import SwiftUI
import UniformTypeIdentifiers

/// Helper class that loads assets from the photo library.
public class PhotoAssetLoader: NSObject, ObservableObject {

    @Injected(\.chatClient) private var chatClient

    @Published var loadedImages = [String: UIImage]()

    /// Loads an image from the provided asset.
    func loadImage(from asset: PHAsset) {
        if loadedImages[asset.localIdentifier] != nil {
            return
        }

        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 250, height: 250),
            contentMode: .aspectFit,
            options: options
        ) { [weak self] image, _ in
            guard let self = self, let image = image else { return }
            self.loadedImages[asset.localIdentifier] = image
        }
    }

    /// Poppin (2026-11-06): the long edge every photo is re-encoded to before it is measured or
    /// uploaded. The server stores 1600 px (`svchat.ProcessImage`), so nothing above this ever
    /// reaches the wire.
    static let uploadMaxPixelSize: CGFloat = 2048
    static let uploadJPEGQuality: CGFloat = 0.85

    /// Re-encodes the image at `sourceURL` as a bounded JPEG in the app's temp folder and returns
    /// that file. Photos hands the picker its full-quality JPEG rendition, which runs 8 to 14 MB
    /// on a 24 MP iPhone (far more at 48 MP or ProRAW) — above the 10 MB cap, so every photo from
    /// such a phone used to be refused before any upload (the "Attachment size exceed the limit"
    /// alert on each pick). ImageIO downsamples while decoding, so the full bitmap of a 48 MP
    /// original is never held; EXIF rotation is baked in; HEIC, PNG and JPEG all come out JPEG.
    /// `nil` when ImageIO cannot read the file — callers keep the original URL then.
    static func prepareImageForUpload(at sourceURL: URL) -> URL? {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: uploadMaxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: uploadJPEGQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationURL
    }

    func compressAsset(at url: URL, type: AssetType, completion: @escaping (URL?) -> Void) {
        if type == .image {
            // An oversized photo is re-encoded, never refused; the original stays if ImageIO
            // cannot read it (the completion used to be skipped for images — stuck spinner).
            completion(PhotoAssetLoader.prepareImageForUpload(at: url) ?? url)
            return
        }
        if type == .video {
            let compressedURL = NSURL.fileURL(withPath: NSTemporaryDirectory() + UUID().uuidString + ".mp4")
            compressVideo(inputURL: url, outputURL: compressedURL) { exportSession in
                guard let session = exportSession else {
                    return
                }

                switch session.status {
                case .completed:
                    completion(compressedURL)
                default:
                    completion(nil)
                }
            }
        }
    }

    func assetExceedsAllowedSize(url: URL?, type: AssetType) -> Bool {
        _ = url?.startAccessingSecurityScopedResource()
        let maxSize = type == .video
            ? chatClient.config.maxVideoAttachmentSize
            : chatClient.config.maxImageAttachmentSize
        if let assetURL = url,
           let file = try? AttachmentFile(url: assetURL),
           file.size >= maxSize {
            return true
        } else {
            return false
        }
    }

    private func compressVideo(
        inputURL: URL,
        outputURL: URL,
        handler: @escaping (_ exportSession: AVAssetExportSession?) -> Void
    ) {
        let urlAsset = AVURLAsset(url: inputURL, options: nil)

        guard let exportSession = AVAssetExportSession(
            asset: urlAsset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            handler(nil)
            return
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.exportAsynchronously {
            handler(exportSession)
        }
    }

    /// Clears the cache when there's memory warning.
    func didReceiveMemoryWarning() {
        loadedImages = [String: UIImage]()
    }
}

public extension PHAsset {
    /// Return a formatted duration string of an asset.
    var durationString: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        var minutesString = "\(minutes)"
        var secondsString = "\(seconds)"
        if minutes < 10 {
            minutesString = "0" + minutesString
        }
        if seconds < 10 {
            secondsString = "0" + secondsString
        }

        return "\(minutesString):\(secondsString)"
    }
}

extension PHAsset: Identifiable {
    public var id: String {
        localIdentifier
    }
}

/// Helper collection that allows iteration over the fetched assets from the photo library.
public struct PHFetchResultCollection: RandomAccessCollection, Equatable {
    public typealias Element = PHAsset
    public typealias Index = Int

    public let fetchResult: PHFetchResult<PHAsset>

    public var endIndex: Int { fetchResult.count }
    public var startIndex: Int { 0 }

    public init(fetchResult: PHFetchResult<PHAsset>) {
        self.fetchResult = fetchResult
    }

    public subscript(position: Int) -> PHAsset {
        fetchResult.object(at: position)
    }
}
