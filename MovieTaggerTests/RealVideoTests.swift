import XCTest
import AVFoundation
@testable import MovieTagger

final class RealVideoTests: XCTestCase {
    func testTaggedVideoRetainsEncodedSamplesAndReadableDuration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("video.mp4")
        let encoder = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        encoder.add(input)
        XCTAssertTrue(encoder.startWriting())
        encoder.startSession(atSourceTime: .zero)
        for frame in 0..<3 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard input.isReadyForMoreMediaData else { throw CocoaError(.fileWriteUnknown) }
            var pixel: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &pixel), kCVReturnSuccess)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 50), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 3)))
        }
        input.markAsFinished()
        await encoder.finishWriting()
        XCTAssertEqual(encoder.status, .completed, "\(String(describing: encoder.error))")
        let before = try await encodedSamples(url)
        let durationBefore = try await AVURLAsset(url: url).load(.duration)
        let metadataSnapshot = try await MainActor.run { MovieMetadata(from: try MP4Fixtures.model()) }
        try await MetadataWriter().writeMetadata(fileURL: url, metadata: metadataSnapshot, progressHandler: { _ in })
        let after = try await encodedSamples(url)
        let durationAfter = try await AVURLAsset(url: url).load(.duration)
        XCTAssertFalse(before.isEmpty)
        XCTAssertEqual(before, after)
        XCTAssertEqual(durationBefore, durationAfter)
        let metadata = try await AVURLAsset(url: url).load(.commonMetadata)
        XCTAssertTrue(metadata.contains { $0.commonKey == .commonKeyTitle })
    }

    private func encodedSamples(_ url: URL) async throws -> [Data] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: nil)
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        var samples: [Data] = []
        while let sample = output.copyNextSampleBuffer() {
            // AVAssetReader can emit zero-byte end/discontinuity markers.
            guard CMSampleBufferGetTotalSampleSize(sample) > 0 else { continue }
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let length = bytes.count
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            samples.append(bytes)
        }
        XCTAssertEqual(reader.status, .completed)
        return samples
    }
}
