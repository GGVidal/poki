import AudioToolbox
import AVFoundation
import Foundation
import WebRTC

@MainActor
struct OpeningVoiceCapture {
    let audio: OpeningVoiceAudio
    let factory: RTCPeerConnectionFactory

    init() throws {
        let audio = OpeningVoiceAudio()
        try audio.startCapture()
        self.audio = audio
        factory = RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil, audioDevice: audio)
    }
}

/// Captures the Action Button's opening words before WebRTC is ready. The same voice-processed
/// audio engine supplies WebRTC after connect, so there is no second microphone or audio upload.
final class OpeningVoiceAudio: NSObject, RTCAudioDevice, @unchecked Sendable {
    private static let sampleRate = 48_000.0
    private static let maxOpeningFrames = Int(sampleRate) * 30
    private static let channelFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true
    )!

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var delegate: RTCAudioDeviceDelegate?
    private var recording = false
    private var playing = false
    private var recordingInitialized = false
    private var playoutInitialized = false
    private var canSend = false
    private var sentAudio = false
    private var finished = false
    private var overflow = false
    private var queued = [Int16]()
    private var readIndex = 0
    private var quietFrames = 0

    let deviceInputSampleRate = OpeningVoiceAudio.sampleRate
    let deviceOutputSampleRate = OpeningVoiceAudio.sampleRate
    let inputNumberOfChannels = 1
    let outputNumberOfChannels = 1
    let inputIOBufferDuration = 0.01
    let outputIOBufferDuration = 0.01
    let inputLatency: TimeInterval = 0
    let outputLatency: TimeInterval = 0
    var isInitialized: Bool { lock.withLock { delegate != nil } }
    var isRecordingInitialized: Bool { lock.withLock { recordingInitialized } }
    var isPlayoutInitialized: Bool { lock.withLock { playoutInitialized } }
    var isRecording: Bool { lock.withLock { recording } }
    var isPlaying: Bool { lock.withLock { playing } }

    @MainActor func startCapture() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        var tapInstalled = false
        do {
            let microphone = engine.inputNode
            try microphone.setVoiceProcessingEnabled(true)
            let inputFormat = microphone.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
                  let converter = AVAudioConverter(from: inputFormat, to: Self.channelFormat) else {
                throw VoiceError.noWebRTC
            }
            let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
            let player = makePlayer(format: playbackFormat)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
            installTap(on: microphone, format: inputFormat, converter: converter)
            tapInstalled = true
            engine.prepare()
            try engine.start()
        } catch {
            engine.stop()
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }
    }

    /// The media track drains the opening audio after session readiness, in front of any live input.
    func allowSending() -> Bool {
        lock.withLock {
            guard !overflow, !finished else { return false }
            canSend = true
            return true
        }
    }

    func keepForDictation() -> Bool {
        lock.withLock {
            guard !sentAudio, !finished else { return false }
            canSend = false
            return true
        }
    }

    /// Takes unsent audio only. After any media has gone out, a fallback must not repeat the task.
    @MainActor func stopCapture() -> AVAudioPCMBuffer? {
        let stopped: (wasRunning: Bool, completeRecording: [Int16]?) = lock.withLock {
            guard !finished else { return (false, nil) }
            finished = true
            let samples = sentAudio || overflow ? nil : queued
            queued.removeAll()
            return (true, samples)
        }
        guard stopped.wasRunning else { return nil }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let samples = stopped.completeRecording, !samples.isEmpty,
              let audio = AVAudioPCMBuffer(pcmFormat: Self.channelFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let data = audio.int16ChannelData?[0] else { return nil }
        audio.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { data.update(from: $0.baseAddress!, count: $0.count) }
        return audio
    }

    private func installTap(on microphone: AVAudioInputNode, format: AVAudioFormat, converter: AVAudioConverter) {
        microphone.installTap(onBus: 0, bufferSize: 480, format: format) { [weak self] buffer, time in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * Self.sampleRate / format.sampleRate)) + 64
            guard let self, let pcm = AVAudioPCMBuffer(pcmFormat: Self.channelFormat, frameCapacity: capacity) else { return }
            var supplied = false
            let status = converter.convert(to: pcm, error: nil) { _, inputStatus in
                inputStatus.pointee = supplied ? .noDataNow : .haveData
                defer { supplied = true }
                return supplied ? nil : buffer
            }
            guard status != .error, pcm.frameLength > 0 else { return }
            self.input(pcm, at: time)
        }
    }

    private func input(_ pcm: AVAudioPCMBuffer, at time: AVAudioTime) {
        guard let source = pcm.int16ChannelData?[0] else { return }
        let count = Int(pcm.frameLength)
        let sourceFrames = UnsafeBufferPointer(start: source, count: count)
        let (delegate, audio): (RTCAudioDeviceDelegate?, [Int16]?) = lock.withLock {
            guard !finished else { return (nil, nil) }
            if !canSend || !recording {
                let remaining = max(0, Self.maxOpeningFrames - queued.count)
                queued.append(contentsOf: sourceFrames.prefix(remaining))
                if count > remaining { overflow = true }
                return (nil, nil)
            }
            guard let delegate, !overflow else { return (nil, nil) }
            sentAudio = true
            guard readIndex < queued.count else { return (delegate, nil) }

            // Catch up during a pause. Keep a full second of quiet to separate utterances, then
            // omit additional quiet frames until the opening audio has caught up to the live mic.
            let isQuiet = sourceFrames.allSatisfy { abs(Int($0)) < 100 }
            quietFrames = isQuiet ? quietFrames + count : 0
            if quietFrames <= Int(Self.sampleRate) {
                queued.append(contentsOf: sourceFrames)
            }
            let end = min(readIndex + count, queued.count)
            let audio = Array(queued[readIndex..<end])
            readIndex = end
            if readIndex == queued.count {
                queued.removeAll()
                readIndex = 0
            } else if readIndex >= Int(Self.sampleRate) {
                queued.removeFirst(readIndex)
                readIndex = 0
            }
            return (delegate, audio)
        }
        guard let delegate else { return }
        if let audio {
            audio.withUnsafeBufferPointer { deliver($0, to: delegate, at: time) }
        } else {
            deliver(sourceFrames, to: delegate, at: time)
        }
    }

    private func deliver(_ samples: UnsafeBufferPointer<Int16>, to delegate: RTCAudioDeviceDelegate, at time: AVAudioTime) {
        var flags: AudioUnitRenderActionFlags = []
        var timestamp = time.audioTimeStamp
        var audio = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: UInt32(samples.count * MemoryLayout<Int16>.stride),
            mData: UnsafeMutableRawPointer(mutating: samples.baseAddress)
        ))
        _ = delegate.deliverRecordedData(&flags, &timestamp, 0, UInt32(samples.count), &audio, nil, nil)
    }

    private func makePlayer(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [weak self] silent, timestamp, count, output in
            guard let self, let destination = output.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
                return kAudio_ParamError
            }
            let delegate = self.lock.withLock { self.playing && !self.finished ? self.delegate : nil }
            guard let delegate else {
                silent.pointee = true
                destination.update(repeating: 0, count: Int(count))
                return noErr
            }
            return withUnsafeTemporaryAllocation(of: Int16.self, capacity: Int(count)) { samples in
                var flags: AudioUnitRenderActionFlags = []
                var audio = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: count * UInt32(MemoryLayout<Int16>.stride), mData: samples.baseAddress
                ))
                let status = delegate.getPlayoutData(&flags, timestamp, 0, count, &audio)
                guard status == noErr else { return status }
                if flags.contains(.unitRenderAction_OutputIsSilence) {
                    silent.pointee = true
                    destination.update(repeating: 0, count: Int(count))
                } else {
                    for index in samples.indices { destination[index] = Float(samples[index]) / 32_768 }
                }
                return noErr
            }
        }
    }

    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        lock.withLock { self.delegate = delegate }
        return true
    }
    func terminateDevice() -> Bool {
        lock.withLock {
            delegate = nil
            recording = false
            playing = false
            recordingInitialized = false
            playoutInitialized = false
        }
        return true
    }
    func initializeRecording() -> Bool { lock.withLock { recordingInitialized = true }; return true }
    func initializePlayout() -> Bool { lock.withLock { playoutInitialized = true }; return true }
    func startRecording() -> Bool { lock.withLock { recording = true }; return true }
    func stopRecording() -> Bool { lock.withLock { recording = false }; return true }
    func startPlayout() -> Bool { lock.withLock { playing = true }; return true }
    func stopPlayout() -> Bool { lock.withLock { playing = false }; return true }
}
