//
//  Spitfire.swift
//  Pods
//
//  Created by seanmcneil on 3/8/17.
//
//

import AVFoundation
import UIKit

@objc public class Spitfire: NSObject {

    private var videoWriter: AVAssetWriter?

    private var outputURL: URL {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let documentURL = URL(fileURLWithPath: documentsPath)

        return documentURL.appendingPathComponent("output.m4v")
    }

    /// Produces a video based on the contents of a UIImage array
    ///
    /// - Parameters:
    ///   - images: Images to use for creating video. Should all have the same dimensions
    ///   - fps: Frames per second, with a default value of 30
    ///   - progress: Handler that will return a fractional value indicating percent complete
    ///   - success: Handler that will return a URL of the completed video if successful
    ///   - failure: Handler that will return an error message if one occurs
    @objc public func makeVideo(with images: [UIImage], fps: Int32 = 30, progress: @escaping ((Progress) -> ()), success: @escaping ((URL) -> ())) throws {
        guard let size = images.first?.size else {
            throw(SpitfireError.ImageArrayEmpty)
        }

        guard fps > 0 && fps <= 60 else {
            let message = NSLocalizedString("Framerate must be between 1 and 60", comment: "")
            throw(SpitfireError.InvalidFramerate(message))
        }

        //        guard (size.width .truncatingRemainder(dividingBy: 16.0)) == 0 else {
        //            let message = NSLocalizedString("Image width must be divisble by 16", comment: "")
        //            throw(SpitfireError.ImageDimensionsMultiplierFailure(message))
        //        }

        try? FileManager.default.removeItem(at: outputURL)

        do {
            try videoWriter = AVAssetWriter(outputURL: outputURL, fileType: AVFileType.m4v)
        } catch let error {
            throw(error)
        }

        guard let videoWriter = videoWriter else {
            throw(SpitfireError.VideoWriterFailure)
        }

        let videoSettings: [String : Any] = [
            AVVideoCodecKey  : AVVideoCodecH264,
            AVVideoWidthKey  : size.width,
            AVVideoHeightKey : size.height,
            ]

        let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)

        let sourceBufferAttributes: [String : Any] = [
            (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32ARGB),
            (kCVPixelBufferWidthKey as String): Float(size.width),
            (kCVPixelBufferHeightKey as String): Float(size.height)
        ]

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        assert(videoWriter.canAdd(videoWriterInput))
        videoWriter.add(videoWriterInput)

        if videoWriter.startWriting() {
            videoWriter.startSession(atSourceTime: kCMTimeZero)
            assert(pixelBufferAdaptor.pixelBufferPool != nil)
            let writeQueue = DispatchQueue(label: "writeQueue")
            videoWriterInput.requestMediaDataWhenReady(on: writeQueue, using: { () in
                let frameDuration = CMTimeMake(1, fps)
                let currentProgress = Progress(totalUnitCount: Int64(images.count))
                var frameCount: Int64 = 0
                print("Encoding total number of images: \(images.count)")

                while(Int(frameCount) < images.count) {
                    print("Encoding frame \(frameCount) / \(images.count)")
                    // Will continue to loop until the video writer is able to write, which effectively handles buffer backups
                    if videoWriterInput.isReadyForMoreMediaData {
                        let lastFrameTime = CMTimeMake(frameCount, fps)
                        let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)
                        let image = images[Int(frameCount)]

                        do {
                            guard image.size == size else {
                                throw(SpitfireError.ImageDimensionsMatchFailure)
                            }
                        } catch { } // Do not throw here

                        do {
                            try self.append(pixelBufferAdaptor: pixelBufferAdaptor, with: image, at: presentationTime, success: {
                                frameCount += 1
                                currentProgress.completedUnitCount = frameCount
                                progress(currentProgress)
                            })
                        } catch {
                            print("Error is %\(error)")
                        } // Do not throw here
                    }
                }

                videoWriterInput.markAsFinished()
                videoWriter.finishWriting { [weak self] () -> Void in
                    guard let strongSelf = self else { return }

                    success(strongSelf.outputURL)
                }
            })
        }
    }
}
