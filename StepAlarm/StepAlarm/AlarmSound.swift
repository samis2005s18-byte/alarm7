import AVFoundation

/// Keeps the alarm ringing inside the app while the user walks. Tapping
/// "Walk" dismisses the system alarm alert, so without this the sound would
/// stop the moment the Wake Up screen opens.
@MainActor
final class AlarmSound {
    static let shared = AlarmSound()

    private var player: AVAudioPlayer?

    private init() {}

    func start() {
        guard player == nil else { return }
        do {
            // .playback rings even with the Silent switch on, and keeps
            // playing with the screen locked (UIBackgroundModes: audio).
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.makeBeepWAV())
            player.numberOfLoops = -1
            player.volume = 1
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One second of classic alarm beeping — two short 880 Hz beeps — as a
    /// 16-bit mono WAV, generated in code so no sound file is needed.
    private static func makeBeepWAV() -> Data {
        let sampleRate = 44_100
        var samples = [Int16](repeating: 0, count: sampleRate)
        for beepStart in [0.0, 0.25] {
            let first = Int(beepStart * Double(sampleRate))
            let count = Int(0.15 * Double(sampleRate))
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                // Short fade in/out so the beeps don't click.
                let envelope = min(1, Double(i) / 200, Double(count - i) / 200)
                samples[first + i] = Int16(sin(2 * .pi * 880 * t) * envelope * 30_000)
            }
        }

        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + byteCount))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))              // fmt chunk size
        append(UInt16(1))               // PCM
        append(UInt16(1))               // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))  // byte rate
        append(UInt16(2))               // block align
        append(UInt16(16))              // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(byteCount))
        for sample in samples { append(sample) }
        return data
    }
}
