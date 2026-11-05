import Foundation
import UIKit
import TelegramCore
import SwiftSignalKit
import Display
import Pdf
import AVFoundation

public struct ICloudFileResourceId {
    public let urlData: String
    public let thumbnail: Bool
    
    public var uniqueId: String {
        if self.thumbnail {
            return "icloud-thumb-\(enginePersistentHash32(self.urlData))"
        } else {
            return "icloud-\(enginePersistentHash32(self.urlData))"
        }
    }
    
    public var hashValue: Int {
        return self.uniqueId.hashValue
    }
}

public class ICloudFileResource: TelegramMediaResource {
    public let urlData: String
    public let thumbnail: Bool
    
    public var size: Int64? {
        return nil
    }
    
    public init(urlData: String, thumbnail: Bool) {
        self.urlData = urlData
        self.thumbnail = thumbnail
    }
    
    public required init(decoder: EnginePostboxDecoder) {
        self.urlData = decoder.decodeStringForKey("url", orElse: "")
        self.thumbnail = decoder.decodeBoolForKey("thumb", orElse: false)
    }
    
    public func encode(_ encoder: EnginePostboxEncoder) {
        encoder.encodeString(self.urlData, forKey: "url")
        encoder.encodeBool(self.thumbnail, forKey: "thumb")
    }
    
    public var id: EngineRawMediaResourceId {
        return EngineRawMediaResourceId(ICloudFileResourceId(urlData: self.urlData, thumbnail: self.thumbnail).uniqueId)
    }

    public func isEqual(to: EngineRawMediaResource) -> Bool {
        if let to = to as? ICloudFileResource {
            if self.urlData != to.urlData || self.thumbnail != to.thumbnail {
                return false
            }
            return true
        } else {
            return false
        }
    }
}

public struct ICloudFileDescription {
    public struct AudioMetadata {
        public let title: String?
        public let performer: String?
        public let duration: Int
        public let hasAudioArtwork: Bool
    }
    
    public let urlData: String
    public let fileName: String
    public let fileSize: Int
    public let audioMetadata: AudioMetadata?
}

private let audioFileExtensions: Set<String> = ["mp3", "m4a", "aac", "flac"]

private func validatedAudioArtworkData(_ data: Data?) -> Data? {
    guard let data, UIImage(data: data) != nil else {
        return nil
    }
    return data
}

private func audioArtworkData(from metadataItem: AVMetadataItem) -> Data? {
    if let data = validatedAudioArtworkData(metadataItem.value(forKey: "dataValue") as? Data) {
        return data
    }
    if let data = metadataItem.value(forKey: "value") as? Data {
        return validatedAudioArtworkData(data)
    }
    if let data = metadataItem.value(forKey: "value") as? NSData {
        return validatedAudioArtworkData(data as Data)
    }
    return nil
}

private func audioArtworkData(from asset: AVURLAsset) -> Data? {
    func firstArtworkData(in metadataItems: [AVMetadataItem]) -> Data? {
        for item in metadataItems {
            if item.commonKey == AVMetadataKey.commonKeyArtwork, let data = audioArtworkData(from: item) {
                return data
            }
        }
        return nil
    }

    if let data = firstArtworkData(in: asset.commonMetadata) {
        return data
    }

    for format in asset.availableMetadataFormats {
        if let data = firstArtworkData(in: asset.metadata(forFormat: format)) {
            return data
        }
    }

    return nil
}

// A readable sandbox/import URL may not need an additional security scope.
private final class ICloudFileAccess {
    private let url: URL
    private let acquired: Bool
    init(_ url: URL) { self.url = url; self.acquired = url.startAccessingSecurityScopedResource() }
    deinit { if self.acquired { self.url.stopAccessingSecurityScopedResource() } }
}

private let iCloudFileReadQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "app.solvgram.document-reads"
    queue.qualityOfService = .userInitiated
    queue.maxConcurrentOperationCount = 4
    return queue
}()

private func descriptionWithUrl(_ url: URL, coordinatedURL: URL? = nil) -> ICloudFileDescription? {
    if #available(iOSApplicationExtension 9.0, iOS 9.0, *) {
        guard url.isFileURL else { return nil }
        let access = ICloudFileAccess(url)
        defer { withExtendedLifetime(access) {} }
        let readURL = coordinatedURL ?? url
        
        guard let urlData = try? url.bookmarkData(options: URL.BookmarkCreationOptions.suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return nil
        }
        
        guard let values = try? readURL.resourceValues(forKeys: Set([.fileSizeKey, .isRegularFileKey])), values.isRegularFile != false, let fileSize = values.fileSize else {
            return nil
        }
        
        // lastPathComponent is already decoded; a second decode corrupts literal '%' names.
        let fileName = url.lastPathComponent
        guard !fileName.isEmpty else { return nil }
        
        var audioMetadata: ICloudFileDescription.AudioMetadata?
        let fileExtension = url.pathExtension.lowercased()
        var hasAudioArtwork = false
        let audioAsset: AVURLAsset?
        if audioFileExtensions.contains(fileExtension) {
            let asset = AVURLAsset(url: readURL)
            audioAsset = asset
            hasAudioArtwork = audioArtworkData(from: asset) != nil
        } else {
            audioAsset = nil
        }
        if ["mp3", "m4a"].contains(fileExtension), let asset = audioAsset {
            let title = AVMetadataItem.metadataItems(from: asset.commonMetadata, withKey: AVMetadataKey.commonKeyTitle, keySpace: AVMetadataKeySpace.common).first?.stringValue
            let performer = AVMetadataItem.metadataItems(from: asset.commonMetadata, withKey: AVMetadataKey.commonKeyArtist, keySpace: AVMetadataKeySpace.common).first?.stringValue
            let duration = CMTimeGetSeconds(asset.duration)
            if duration > 0 {
                audioMetadata = ICloudFileDescription.AudioMetadata(title: title, performer: performer, duration: Int(duration), hasAudioArtwork: hasAudioArtwork)
            }
        } else if fileExtension == "flac", let asset = audioAsset {
            var title: String?
            var performer: String?
            let vorbisComment = AVMetadataFormat(rawValue: "org.xiph.vorbis-comment")
            if asset.availableMetadataFormats.contains(vorbisComment) {
                let items = asset.metadata(forFormat: vorbisComment)
                for item in items {
                    if item.commonKey == AVMetadataKey.commonKeyTitle {
                        title = item.stringValue
                    }
                    if item.commonKey == AVMetadataKey.commonKeyArtist {
                        performer = item.stringValue
                    }
                }
            }
            let duration = CMTimeGetSeconds(asset.duration)
            if duration > 0 {
                audioMetadata = ICloudFileDescription.AudioMetadata(title: title, performer: performer, duration: Int(duration), hasAudioArtwork: hasAudioArtwork)
            }
        }
        
        let result = ICloudFileDescription(
            urlData: urlData.base64EncodedString(),
            fileName: fileName,
            fileSize: fileSize,
            audioMetadata: audioMetadata
        )
        
        
        return result
    } else {
        return nil
    }
}

public func iCloudFileDescription(_ url: URL) -> Signal<ICloudFileDescription?, NoError> {
    return Signal { subscriber in
        guard url.isFileURL else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let access = ICloudFileAccess(url)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [.withoutChanges])
        coordinator.coordinate(with: [intent], queue: iCloudFileReadQueue) { error in
            withExtendedLifetime(access) {
                subscriber.putNext(error == nil ? descriptionWithUrl(url, coordinatedURL: intent.url) : nil)
                subscriber.putCompletion()
            }
        }
        return ActionDisposable { coordinator.cancel() }
    }
}

private final class ICloudFileResourceCopyItem: EngineRawMediaResourceDataFetchCopyLocalItem {
    private let url: URL
    private let access: ICloudFileAccess
    init(url: URL, access: ICloudFileAccess) { self.url = url; self.access = access }

    func copyTo(url destination: URL) -> Bool {
        defer { withExtendedLifetime(self.access) {} }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var error: NSError?
        var copied = false
        coordinator.coordinate(readingItemAt: self.url, options: [.withoutChanges], error: &error) { source in
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                copied = true
            } catch { copied = false }
        }
        return error == nil && copied
    }
}

public func fetchICloudFileResource(resource: ICloudFileResource) -> Signal<EngineMediaResourceDataFetchResult, EngineMediaResourceDataFetchError> {
    return Signal { subscriber in
        subscriber.putNext(.reset)
        
        guard let urlData = Data(base64Encoded: resource.urlData) else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        var bookmarkDataIsStale = false
        guard let url = try? URL(resolvingBookmarkData: urlData, bookmarkDataIsStale: &bookmarkDataIsStale) else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        
        guard url.isFileURL else {
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let access = ICloudFileAccess(url)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        let intent = NSFileAccessIntent.readingIntent(with: url, options: [.withoutChanges])
        coordinator.coordinate(with: [intent], queue: iCloudFileReadQueue) { error in
            withExtendedLifetime(access) {
                guard error == nil else { subscriber.putCompletion(); return }
                if !resource.thumbnail {
                    subscriber.putNext(.copyLocalItem(ICloudFileResourceCopyItem(url: url, access: access)))
                    subscriber.putCompletion()
                    return
                }
                let coordinatedURL = intent.url

                let tempFile = EngineTempBox.shared.tempFile(fileName: "thumb.jpg")
                var data = Data()
                let fileExtension = coordinatedURL.pathExtension.lowercased()
                let isAudioFile = audioFileExtensions.contains(fileExtension)

                if isAudioFile, let artworkData = audioArtworkData(from: AVURLAsset(url: coordinatedURL)), let originalImage = UIImage(data: artworkData), let image = generateScaledImage(image: originalImage, size: originalImage.size.fitted(CGSize(width: 256, height: 256.0))), let jpegData = image.jpegData(compressionQuality: 0.5) {
                    data = jpegData
                } else if !isAudioFile {
                    if let imageData = try? Data(contentsOf: coordinatedURL, options: .mappedIfSafe), let originalImage = UIImage(data: imageData), let image = generateScaledImage(image: originalImage, size: originalImage.size.fitted(CGSize(width: 256, height: 256.0))), let jpegData = image.jpegData(compressionQuality: 0.5) {
                        data = jpegData
                    } else if let image = generatePdfPreviewImage(url: coordinatedURL, size: CGSize(width: 256, height: 256.0)), let jpegData = image.jpegData(compressionQuality: 0.5) {
                        data = jpegData
                    }
                }
                if let _ = try? data.write(to: URL(fileURLWithPath: tempFile.path)) {
                    subscriber.putNext(.moveTempFile(file: tempFile))
                }
                subscriber.putCompletion()
            }
        }
        return ActionDisposable { coordinator.cancel() }
    }
}
