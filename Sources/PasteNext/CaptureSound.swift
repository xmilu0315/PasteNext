import AppKit
import Foundation

enum CaptureSound: String, CaseIterable, Identifiable {
    case click, tick, pop, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .click: return L("咔嗒 · Clean Click", "Clean Click")
        case .tick: return L("轻触 · Tick", "Light Tick")
        case .pop: return L("气泡 · Pop", "Pop")
        case .none: return L("静音", "Silent")
        }
    }

    static var selected: CaptureSound {
        let raw = UserDefaults.standard.string(forKey: "captureSoundName") ?? CaptureSound.click.rawValue
        return CaptureSound(rawValue: raw) ?? .click
    }

    static func migrateStoredValue() {
        let defaults = UserDefaults.standard
        let existing = defaults.string(forKey: "captureSoundName")
        if let existing, CaptureSound(rawValue: existing) != nil { return }
        if defaults.object(forKey: "captureSound") as? Bool == false {
            defaults.set(CaptureSound.none.rawValue, forKey: "captureSoundName")
        } else {
            defaults.set(CaptureSound.click.rawValue, forKey: "captureSoundName")
        }
    }

    @MainActor private static var players: [CaptureSound: NSSound] = [:]

    @MainActor
    static func playSelected() { play(selected) }

    static func canLoad(_ sound: CaptureSound) -> Bool {
        NSSound(data: wavData(for: sound)) != nil
    }

    @MainActor
    static func play(_ sound: CaptureSound) {
        guard sound != .none else { return }
        let player: NSSound
        if let cached = players[sound] {
            player = cached
        } else {
            guard let generated = NSSound(data: wavData(for: sound)) else { return }
            players[sound] = generated
            player = generated
        }
        if player.isPlaying { player.stop() }
        player.volume = 0.82
        player.play()
    }

    private static func wavData(for sound: CaptureSound) -> Data {
        let sampleRate = 44_100
        let duration: Double
        switch sound {
        case .click: duration = 0.065
        case .tick: duration = 0.045
        case .pop: duration = 0.085
        case .none: duration = 0.01
        }
        let sampleCount = Int(duration * Double(sampleRate))
        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)
        var noiseState: UInt32 = 0x9E3779B9

        for index in 0..<sampleCount {
            let t = Double(index) / Double(sampleRate)
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            let noise = (Double(noiseState >> 8) / Double(1 << 24) * 2 - 1)

            let value: Double
            switch sound {
            case .click:
                // Two very short mechanical impulses: a crisp "ka-ta" instead of a musical chime.
                let first = exp(-t * 220) * (sin(2 * .pi * 1_950 * t) * 0.58 + sin(2 * .pi * 3_400 * t) * 0.20)
                let secondTime = max(0, t - 0.017)
                let second = t > 0.017 ? exp(-secondTime * 300) * sin(2 * .pi * 1_300 * secondTime) * 0.42 : 0
                value = (first + second) * 0.58 + noise * exp(-t * 650) * 0.10
            case .tick:
                value = sin(2 * .pi * 3_100 * t) * exp(-t * 340) * 0.42
                    + noise * exp(-t * 900) * 0.08
            case .pop:
                let frequency = 760 - min(t / duration, 1) * 440
                value = sin(2 * .pi * frequency * t) * exp(-t * 95) * 0.48
                    + noise * exp(-t * 700) * 0.04
            case .none:
                value = 0
            }

            let attack = min(1, t / 0.0012)
            let clamped = max(-1, min(1, value * attack))
            samples.append(Int16(clamped * Double(Int16.max) * 0.82))
        }

        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            var little = sample.littleEndian
            withUnsafeBytes(of: &little) { pcm.append(contentsOf: $0) }
        }

        var wav = Data()
        func appendASCII(_ string: String) { wav.append(contentsOf: string.utf8) }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { wav.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        appendUInt32(UInt32(36 + pcm.count))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}
