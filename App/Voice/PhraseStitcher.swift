import AVFoundation

/// Склейка слов в одну фразу: обрезка тишины, выравнивание громкости, короткие кроссфейды.
enum PhraseStitcher {
    static let sampleRate = 44_100.0
    static var format: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    }

    // MARK: Чистая обработка (тестируется)

    /// Убирает тишину по краям, оставляя небольшой запас.
    static func trimSilence(_ samples: [Float], threshold: Float = 0.02, padding: Int = 441) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold }) else { return [] }
        let lo = max(0, first - padding), hi = min(samples.count - 1, last + padding)
        return Array(samples[lo...hi])
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    /// Нормализует к целевому RMS с ограничением пика.
    static func normalize(_ samples: [Float], targetRMS: Float = 0.12) -> [Float] {
        let current = rms(samples)
        guard current > 0 else { return samples }
        let peak = samples.map(abs).max() ?? 1
        let gain = min(targetRMS / current, 0.98 / max(peak, 1e-6))
        return samples.map { $0 * gain }
    }

    /// Склеивает фрагменты с линейным кроссфейдом.
    static func stitch(_ parts: [[Float]], crossfade: Int = 1323) -> [Float] {
        var out: [Float] = []
        for part in parts where !part.isEmpty {
            let fade = min(crossfade, out.count, part.count)
            if fade > 0 {
                let start = out.count - fade
                for i in 0..<fade {
                    let t = Float(i + 1) / Float(fade + 1)
                    out[start + i] = out[start + i] * (1 - t) + part[i] * t
                }
                out += part[fade...]
            } else {
                out += part
            }
        }
        return out
    }

    /// Полный конвейер для слов: обрезка → громкость → склейка.
    static func process(_ words: [[Float]], targetRMS: Float = 0.12) -> [Float] {
        stitch(words.map { normalize(trimSilence($0), targetRMS: targetRMS) })
    }

    // MARK: Файлы

    /// Читает файл и приводит к 44.1 кГц моно float.
    static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: input)
        let target = format
        if file.processingFormat == target {
            return Array(UnsafeBufferPointer(start: input.floatChannelData![0], count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else { return [] }
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }

    static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1))) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
