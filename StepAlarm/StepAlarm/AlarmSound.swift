import AudioToolbox
import AVFoundation

/// Keeps the alarm ringing inside the app while the user walks. Tapping
/// "Walk" dismisses the system alarm alert, so without this the sound would
/// stop the moment the Wake Up screen opens.
@MainActor
final class AlarmSound {
    static let shared = AlarmSound()

    private var player: AVAudioPlayer?
    /// True from `start()` until `stop()`: the sound should be playing.
    private var wantsSound = false
    /// Vibrates alongside the sound (so turning the volume down doesn't make
    /// the alarm go quiet) and re-checks that the sound is really playing.
    private var heartbeat: Timer?
    private var interruptionObserver: NSObjectProtocol?

    private init() {}

    func start() {
        wantsSound = true
        ensurePlaying()
        if heartbeat == nil {
            heartbeat = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    AlarmSound.shared.ensurePlaying()
                }
            }
        }
        if interruptionObserver == nil {
            // A call, Siri or the system alarm can take the audio away; when
            // it gives it back, pick the alarm sound up again.
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { AlarmSound.shared.ensurePlaying() }
            }
        }
    }

    /// Starts (or restarts) the sound if it should be playing but isn't.
    /// iOS can refuse to start audio while the app is still in the background
    /// or while the system alarm is sounding, so this is retried by the
    /// heartbeat and when the app comes to the front, instead of trying once.
    func ensurePlaying() {
        guard wantsSound else { return }
        if let player, player.isPlaying { return }
        do {
            // .playback rings even with the Silent switch on, and keeps
            // playing with the screen locked (UIBackgroundModes: audio).
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try self.player ?? AVAudioPlayer(data: Self.makeBeepWAV())
            player.numberOfLoops = -1
            player.volume = 1
            player.play()
            self.player = player
        } catch {
            // Not allowed yet — the next heartbeat or foregrounding retries.
        }
    }

    func stop() {
        wantsSound = false
        heartbeat?.invalidate()
        heartbeat = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
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
