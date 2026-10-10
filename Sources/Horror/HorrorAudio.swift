import AVFoundation

/// Every sound in the horror game, synthesised at launch (no audio files):
/// a droning house, footsteps, a heartbeat, creaks, whispers and the scream.
final class HorrorAudio {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let ambience = AVAudioPlayerNode()
    private let heart = AVAudioPlayerNode()
    private let steps = AVAudioPlayerNode()
    private let creature = AVAudioPlayerNode()
    private var effects: [AVAudioPlayerNode] = []
    private var nextEffect = 0

    private var droneBuffer: AVAudioPCMBuffer!
    private var heartBuffer: AVAudioPCMBuffer!
    private var stepBuffers: [AVAudioPCMBuffer] = []
    private var creatureStepBuffer: AVAudioPCMBuffer!
    private var creakBuffer: AVAudioPCMBuffer!
    private var whisperBuffer: AVAudioPCMBuffer!
    private var screamBuffer: AVAudioPCMBuffer!
    private var pickupBuffer: AVAudioPCMBuffer!
    private var rattleBuffer: AVAudioPCMBuffer!

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        effects = (0..<4).map { _ in AVAudioPlayerNode() }
        for node in [ambience, heart, steps, creature] + effects {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
        buildSounds()
        try? engine.start()
        for node in [ambience, heart, steps, creature] + effects { node.play() }
    }

    func startAmbience() {
        ambience.stop()
        ambience.volume = 0.9
        ambience.scheduleBuffer(droneBuffer, at: nil, options: .loops, completionHandler: nil)
        ambience.play()
    }

    func stop() {
        engine.stop()
    }

    func footstep(volume: Float) {
        steps.volume = volume
        steps.scheduleBuffer(stepBuffers.randomElement()!, at: nil, options: .interrupts, completionHandler: nil)
    }

    func heartbeat(volume: Float) {
        heart.volume = volume
        heart.scheduleBuffer(heartBuffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func creatureStep(volume: Float, pan: Float) {
        creature.volume = volume
        creature.pan = pan
        creature.scheduleBuffer(creatureStepBuffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func creak(volume: Float, pan: Float) { effect(creakBuffer, volume: volume, pan: pan) }
    func whisper(volume: Float, pan: Float) { effect(whisperBuffer, volume: volume, pan: pan) }
    func pickup() { effect(pickupBuffer, volume: 0.7, pan: 0) }
    func lockedDoor() { effect(rattleBuffer, volume: 0.8, pan: 0) }

    func scream() {
        ambience.volume = 0.2
        effect(screamBuffer, volume: 1, pan: 0)
    }

    private func effect(_ buffer: AVAudioPCMBuffer, volume: Float, pan: Float) {
        let node = effects[nextEffect]
        nextEffect = (nextEffect + 1) % effects.count
        node.volume = volume
        node.pan = pan
        node.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    // MARK: - Synthesis

    private func makeBuffer(seconds: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            data[i] = Float(max(-1, min(1, sample(Double(i) / format.sampleRate))))
        }
        return buffer
    }

    private func noise() -> Double { Double.random(in: -1...1) }

    private func buildSounds() {
        let tau = 2 * Double.pi

        // Low house drone: rumbling brown noise and a slow-breathing hum.
        // The tones complete whole cycles in 8 s so the loop is seamless.
        var brown = 0.0
        droneBuffer = makeBuffer(seconds: 8) { t in
            brown = brown * 0.995 + self.noise() * 0.02
            let edge = min(1, min(t, 8 - t) / 0.3)
            let breathe = 0.6 + 0.4 * sin(tau * 0.25 * t)
            return brown * 1.6 * edge + sin(tau * 48 * t) * 0.07 * breathe + sin(tau * 73.5 * t) * 0.03
        }

        // "Lub-dub".
        heartBuffer = makeBuffer(seconds: 0.6) { t in
            func thump(_ start: Double, _ level: Double) -> Double {
                let u = t - start
                return u < 0 ? 0 : sin(tau * 52 * u) * exp(-u * 16) * level
            }
            return thump(0, 0.9) + thump(0.2, 0.6)
        }

        // A few slightly different creaky floorboard footsteps.
        stepBuffers = (0..<3).map { _ in
            var low = 0.0
            let pitch = Double.random(in: 0.12...0.25)
            return makeBuffer(seconds: 0.22) { t in
                low += (self.noise() - low) * pitch
                return low * exp(-t * 28) * 1.4
            }
        }

        // Heavy, dragging steps for the creature.
        var heavy = 0.0
        creatureStepBuffer = makeBuffer(seconds: 0.45) { t in
            heavy += (self.noise() - heavy) * 0.05
            return (heavy * 3 + sin(tau * 38 * t) * 0.6) * exp(-t * 9)
        }

        // Door creak: a rough, wavering tone sliding downwards.
        var phase = 0.0
        creakBuffer = makeBuffer(seconds: 1.4) { t in
            let freq = 210 - 90 * t + 12 * sin(tau * 7 * t)
            phase += tau * freq / 44_100
            let rough = 0.5 + 0.5 * sin(tau * 31 * t + 3 * sin(tau * 3 * t))
            let envelope = sin(Double.pi * t / 1.4)
            return (sin(phase) + 0.5 * sin(phase * 2.01) + 0.3 * sin(phase * 3.02)) * rough * envelope * 0.25
        }

        // Whisper: breathy band-limited noise in syllable-like bursts.
        var lowA = 0.0, lowB = 0.0
        whisperBuffer = makeBuffer(seconds: 1.8) { t in
            let n = self.noise()
            lowA += (n - lowA) * 0.5
            lowB += (n - lowB) * 0.08
            let syllables = max(0, sin(tau * 4.3 * t + sin(tau * 1.1 * t)))
            return (lowA - lowB) * syllables * sin(Double.pi * t / 1.8) * 0.6
        }

        // The scream: detuned, distorted, wavering tones and noise.
        screamBuffer = makeBuffer(seconds: 1.6) { t in
            let wobble = 1 + 0.03 * sin(tau * 9 * t)
            var s = 0.0
            for f in [410.0, 437.0, 612.0, 893.0] {
                let p = (f * wobble * (1 - 0.15 * t) * t).truncatingRemainder(dividingBy: 1)
                s += (2 * p - 1) * 0.35
            }
            s += self.noise() * 0.5
            let envelope = min(1, t / 0.02) * exp(-t * 1.6)
            return tanh(s * 2.5) * envelope
        }

        // Soft chime for picking things up.
        pickupBuffer = makeBuffer(seconds: 0.8) { t in
            (sin(tau * 659 * t) * 0.3 + sin(tau * 988 * t) * 0.15) * exp(-t * 5)
        }

        // Locked door rattling in its frame.
        rattleBuffer = makeBuffer(seconds: 0.5) { t in
            let hits = max(0, sin(tau * 14 * t))
            return self.noise() * pow(hits, 8) * exp(-t * 4) * 0.9
        }
    }
}
