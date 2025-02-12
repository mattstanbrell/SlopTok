import Foundation
import UIKit
import AVFoundation
import CoreGraphics

/// Service responsible for converting still images to video files
class ImageToVideoConverter {
    
    /// Converts a UIImage to a video file with a specified duration
    /// - Parameters:
    ///   - image: The UIImage to convert to video
    ///   - duration: Duration of the video in seconds
    ///   - size: Size of the output video
    /// - Returns: URL of the generated video file
    static func convertImageToVideo(image: UIImage, duration: TimeInterval = 3.0, size: CGSize? = nil) async throws -> URL {
        let videoSize = size ?? image.size
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        
        guard let exporter = MP4Exporter(videoSize: videoSize, outputURL: outputURL) else {
            throw NSError(domain: "ImageToVideoConverter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create MP4Exporter"])
        }
        
        // Add the image frame for the specified duration at 60fps
        let frameCount = Int(duration * 60) // 60fps for smooth playback
        let frameDuration = duration / Double(frameCount)
        
        for i in 0..<frameCount {
            let presentationTime = CMTime(seconds: Double(i) * frameDuration, preferredTimescale: 600)
            if !exporter.addImage(image: image, withPresentationTime: presentationTime, waitIfNeeded: true) {
                throw NSError(domain: "ImageToVideoConverter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to add frame to video"])
            }
        }
        
        // Wait for export completion
        await withCheckedContinuation { continuation in
            exporter.stopRecording {
                continuation.resume()
            }
        }
        
        return outputURL
    }
}

// MARK: - MP4Exporter

private class MP4Exporter: NSObject {
    let videoSize: CGSize
    let assetWriter: AVAssetWriter
    let videoWriterInput: AVAssetWriterInput
    let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    
    init?(videoSize: CGSize, outputURL: URL) {
        self.videoSize = videoSize
        
        guard let _assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4) else {
            return nil
        }
        
        self.assetWriter = _assetWriter
        
        let avOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(videoSize.width)),
            AVVideoHeightKey: NSNumber(value: Float(videoSize.height))
        ]
        
        self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)
        self.videoWriterInput.expectsMediaDataInRealTime = true
        self.assetWriter.add(self.videoWriterInput)
        
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(videoSize.width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(videoSize.height))
        ]
        
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: self.videoWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
        )
        
        super.init()
        
        self.assetWriter.startWriting()
        self.assetWriter.startSession(atSourceTime: CMTime.zero)
    }
    
    func addImage(image: UIImage, withPresentationTime presentationTime: CMTime, waitIfNeeded: Bool = false) -> Bool {
        guard let pixelBufferPool = self.pixelBufferAdaptor.pixelBufferPool else {
            print("ERROR: pixelBufferPool is nil")
            return false
        }
        
        guard let pixelBuffer = self.pixelBufferFromImage(
            image: image,
            pixelBufferPool: pixelBufferPool,
            size: self.videoSize
        ) else {
            print("ERROR: Failed to generate pixelBuffer")
            return false
        }
        
        if waitIfNeeded {
            while self.videoWriterInput.isReadyForMoreMediaData == false { }
        }
        
        return self.pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }
    
    func stopRecording(completion: @escaping ()->()) {
        self.videoWriterInput.markAsFinished()
        self.assetWriter.finishWriting(completionHandler: completion)
    }
    
    private func pixelBufferFromImage(image: UIImage, pixelBufferPool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        
        var pixelBufferOut: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        
        guard status == kCVReturnSuccess, let pixelBuffer = pixelBufferOut else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: data,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }
        
        context.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        
        let horizontalRatio = size.width / CGFloat(cgImage.width)
        let verticalRatio = size.height / CGFloat(cgImage.height)
        let aspectRatio = max(horizontalRatio, verticalRatio) // ScaleAspectFill
        
        let newSize = CGSize(
            width: CGFloat(cgImage.width) * aspectRatio,
            height: CGFloat(cgImage.height) * aspectRatio
        )
        
        let x = (newSize.width < size.width) ? (size.width - newSize.width) / 2 : -(newSize.width-size.width) / 2
        let y = (newSize.height < size.height) ? (size.height - newSize.height) / 2 : -(newSize.height-size.height) / 2
        
        context.draw(cgImage, in: CGRect(x: x, y: y, width: newSize.width, height: newSize.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        return pixelBuffer
    }
} 