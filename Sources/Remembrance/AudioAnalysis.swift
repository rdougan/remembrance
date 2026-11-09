import AVFoundation

enum AudioAnalysis {
    /// Seconds into the file where the sound has died away (the last 50 ms window louder than
    /// -40 dB below the peak). Recordings carry seconds of near-silent room tail; the CAF Last Post
    /// ends audibly at ~77 s of its 84 s, so timing from the file's end would start the silence
    /// seven seconds late.
    static func audibleEnd(of url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData else { return nil }

        let frames = Int(buffer.frameLength), channelCount = Int(buffer.format.channelCount)
        let rate = buffer.format.sampleRate
        let window = max(1, Int(rate / 20))
        guard frames > 0 else { return nil }

        func level(_ start: Int, _ end: Int) -> Float {
            var m: Float = 0
            for c in 0..<channelCount {
                let data = channels[c]
                var i = start
                while i < end { m = max(m, abs(data[i])); i += 1 }
            }
            return m
        }

        let peak = level(0, frames)
        guard peak > 0 else { return nil }
        let threshold = peak * 0.01
        var start = (frames - 1) / window * window
        while start >= 0 {
            if level(start, min(frames, start + window)) > threshold {
                return min(Double(frames), Double(start + window)) / rate
            }
            start -= window
        }
        return nil
    }
}
