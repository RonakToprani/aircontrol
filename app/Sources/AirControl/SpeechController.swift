import AVFoundation
import Speech

/// Push-to-talk dictation: the mic is live ONLY between start() and stop() —
/// physically gated by the pinch that drives it. Recognition runs on-device
/// (forced whenever the locale supports it), keeping the project's no-cloud
/// promise: audio never leaves the Mac.
///
/// Lifecycle per dictation: start() spins up an AVAudioEngine tap feeding a
/// buffer recognition request; partials stream to onPartial for the HUD;
/// stop() ends the audio and delivers the FINAL transcript to its completion
/// once the recognizer settles (bounded by a fallback timeout, so a wedged
/// recognizer can't swallow the text). cancel() tears down and delivers nothing.
final class SpeechController {
    /// Live partial transcript, on the main thread — HUD only, never typed.
    var onPartial: ((String) -> Void)?

    private(set) var listening = false
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var pendingFinal: ((String) -> Void)?
    private var generation = 0

    /// "" when usable; otherwise a short HUD-worthy reason.
    var unavailableReason: String {
        if SFSpeechRecognizer.authorizationStatus() == .denied
            || SFSpeechRecognizer.authorizationStatus() == .restricted {
            return "Speech Recognition denied — enable in System Settings"
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            return "Microphone denied — enable in System Settings"
        }
        if recognizer?.isAvailable != true { return "Speech recognition unavailable" }
        return ""
    }

    /// First call primes the two permission prompts and reports false; once
    /// both are granted it starts listening and reports true.
    func start(completion: @escaping (Bool) -> Void) {
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        if speechAuth == .notDetermined || micAuth == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { _ in
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { completion(false) }
                }
            }
            return
        }
        guard speechAuth == .authorized, micAuth == .authorized,
              let recognizer, recognizer.isAvailable, !listening else {
            completion(false)
            return
        }

        latest = ""
        generation += 1
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true // audio never leaves the Mac
        }
        request = req

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { completion(false); return }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer) // audio thread; the request is internally synced
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            request = nil
            completion(false)
            return
        }

        listening = true
        let gen = generation
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                if let r = result {
                    self.latest = r.bestTranscription.formattedString
                    self.onPartial?(self.latest)
                    if r.isFinal { self.deliverFinal() }
                }
                if error != nil { self.deliverFinal() }
            }
        }
        completion(true)
    }

    /// Stops the mic; the completion gets the final transcript ("" if none).
    func stop(completion: @escaping (String) -> Void) {
        guard listening else { completion(""); return }
        listening = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pendingFinal = completion
        request?.endAudio()
        // The recognizer usually finalizes in a few hundred ms; never let the
        // user's words hang on it.
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, gen == self.generation else { return }
            self.deliverFinal()
        }
    }

    /// Tear down without delivering anything (mode off, app disabled).
    func cancel() {
        guard listening || pendingFinal != nil else { return }
        listening = false
        pendingFinal = nil
        generation += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        task?.cancel()
        task = nil
        request = nil
    }

    private func deliverFinal() {
        guard let cb = pendingFinal else { return }
        pendingFinal = nil
        generation += 1
        task?.finish()
        task = nil
        request = nil
        cb(latest)
    }
}
