// crisp-filler — the on-device filler-word detector the engine shells out to.
//
// Reads a 16 kHz mono WAV, computes the SAME log-mel features the model trained on
// (research/filler_classifier/features.py), slides them through a Core ML model,
// and prints filler time-ranges as JSON: {"fillers": [[start, end], …]}.
//
// The mel must match torchaudio's MelSpectrogram exactly. Since n_fft=400 isn't a
// power of two (so vDSP's FFT can't be used), the DFT is done as a BLAS matrix
// multiply (Real = frames·cosBasis, Imag = frames·sinBasis) — mathematically the
// same as the FFT, and fast. The Hann window, reflect padding, HTK mel filterbank,
// power→dB, and fixed normalization all mirror features.py.
//
// Usage: crisp-filler --model <Wren.mlmodel> --audio <in.wav> [--threshold 0.7]

import Accelerate
import CoreML
import Foundation

// MARK: - Model spec (matches Wren.config.json)

enum Spec {
    // Built-in defaults = Wren's values, so the helper works standalone. A model's
    // config.json (--config) overrides them, so each model carries its OWN framing /
    // normalization / tuning and nothing is hardcoded per-model.
    static var sampleRate = 16000
    static var nFFT = 400
    static var hop = 160
    static var nMels = 64
    static var chunkFrames = 25
    static var chunkHopFrames = 10
    static var melMean: Float = -18.5658
    static var melStd: Float = 17.9252
    static var defaultThreshold = 0.85    // conservative: real video is word-dominated, so favor precision
    static var minFiller = 0.30           // drop fleeting fillers (a real "uhh" is longer)
    static let mergeGap = 0.12            // cut-merge spacing — model-agnostic
    static var frameSec: Double { Double(hop) / Double(sampleRate) }   // 0.01
    static var chunkSec: Double { Double(chunkFrames) * frameSec }      // 0.25
    static var nFreqs: Int { nFFT / 2 + 1 }                            // 201

    /// Override the defaults from a model's config.json (the file published next to
    /// the model). Missing keys keep the default — robust to partial/old configs.
    static func load(_ path: String) {
        guard let data = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let v = j["sample_rate"] as? Int { sampleRate = v }
        if let v = j["n_fft"] as? Int { nFFT = v }
        if let v = j["hop_length"] as? Int { hop = v }
        if let v = j["n_mels"] as? Int { nMels = v }
        if let v = j["chunk_frames"] as? Int { chunkFrames = v }
        if let v = j["chunk_hop_sec"] as? Double { chunkHopFrames = Int((v / frameSec).rounded()) }
        if let v = j["mel_mean"] as? Double { melMean = Float(v) }
        if let v = j["mel_std"] as? Double { melStd = Float(v) }
        if let v = j["recommended_threshold"] as? Double { defaultThreshold = v }
        if let v = j["min_filler"] as? Double { minFiller = v }
    }
}

// MARK: - WAV (16-bit PCM mono, as the engine extracts)

func readWav(_ path: String) -> [Float] {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("could not read \(path)")
    }
    // Find the "data" chunk (skip the RIFF header + any chunks before it).
    let bytes = [UInt8](data)
    func u32(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i+1])<<8 | Int(bytes[i+2])<<16 | Int(bytes[i+3])<<24 }
    guard bytes.count > 44, bytes[0] == 0x52, bytes[1] == 0x49 else { fail("not a WAV file") }
    var pos = 12
    var dataStart = 44, dataLen = bytes.count - 44
    while pos + 8 <= bytes.count {
        let id = String(bytes: bytes[pos..<pos+4], encoding: .ascii) ?? ""
        let size = u32(pos + 4)
        if id == "data" { dataStart = pos + 8; dataLen = size; break }
        pos += 8 + size + (size & 1)
    }
    let end = min(dataStart + dataLen, bytes.count)
    var out = [Float](); out.reserveCapacity((end - dataStart) / 2)
    var i = dataStart
    while i + 1 < end {
        let s = Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i+1]) << 8)
        out.append(Float(s) / 32768.0)
        i += 2
    }
    return out
}

// MARK: - Precomputed bases (built once)

struct Frontend {
    let hann: [Float]               // [nFFT]
    let cosB: [Float]               // [nFFT * nFreqs] row-major
    let sinB: [Float]
    let melFB: [Float]              // [nFreqs * nMels] row-major

    init() {
        let n = Spec.nFFT, freqs = Spec.nFreqs, mels = Spec.nMels
        // Hann, periodic (torch.hann_window(periodic=True))
        hann = (0..<n).map { 0.5 - 0.5 * cos(2.0 * .pi * Float($0) / Float(n)) }
        // DFT basis: e^{-2πi kn/N} → cos(2πkn/N), sin(2πkn/N). Power = re²+im² (sign moot).
        var c = [Float](repeating: 0, count: n * freqs)
        var s = [Float](repeating: 0, count: n * freqs)
        for nn in 0..<n {
            for k in 0..<freqs {
                let a = 2.0 * Double.pi * Double(k) * Double(nn) / Double(n)
                c[nn * freqs + k] = Float(cos(a))
                s[nn * freqs + k] = Float(sin(a))
            }
        }
        cosB = c; sinB = s
        melFB = Frontend.htkMelFilterbank(nFreqs: freqs, nMels: mels,
                                          sampleRate: Double(Spec.sampleRate))
    }

    // torchaudio melscale_fbanks(norm=None, mel_scale="htk")
    static func htkMelFilterbank(nFreqs: Int, nMels: Int, sampleRate: Double) -> [Float] {
        func hzToMel(_ f: Double) -> Double { 2595.0 * log10(1.0 + f / 700.0) }
        func melToHz(_ m: Double) -> Double { 700.0 * (pow(10.0, m / 2595.0) - 1.0) }
        let fMax = sampleRate / 2.0
        let allFreqs = (0..<nFreqs).map { Double($0) * fMax / Double(nFreqs - 1) }
        let mMin = hzToMel(0), mMax = hzToMel(fMax)
        let mPts = (0..<(nMels + 2)).map { mMin + (mMax - mMin) * Double($0) / Double(nMels + 1) }
        let fPts = mPts.map(melToHz)
        let fDiff = (0..<(nMels + 1)).map { fPts[$0 + 1] - fPts[$0] }
        var fb = [Float](repeating: 0, count: nFreqs * nMels)
        for i in 0..<nFreqs {
            for m in 0..<nMels {
                let down = -(fPts[m]     - allFreqs[i]) / fDiff[m]
                let up   =  (fPts[m + 2] - allFreqs[i]) / fDiff[m + 1]
                fb[i * nMels + m] = Float(max(0.0, min(down, up)))
            }
        }
        return fb
    }
}

// MARK: - Mel spectrogram  →  [nMels][T] normalized

func logMel(_ signal: [Float], _ fe: Frontend) -> (mel: [Float], frames: Int) {
    let n = Spec.nFFT, hop = Spec.hop, freqs = Spec.nFreqs, mels = Spec.nMels
    // Reflect-pad n_fft/2 each side (center=True, pad_mode="reflect").
    let pad = n / 2
    var x = [Float](); x.reserveCapacity(signal.count + 2 * pad)
    for i in 0..<pad { x.append(signal[pad - i]) }            // reflect (no edge repeat)
    x.append(contentsOf: signal)
    for i in 0..<pad { x.append(signal[signal.count - 2 - i]) }
    let T = (x.count - n) / hop + 1
    guard T > 0 else { fail("audio too short") }

    // frames [T, n], Hann-windowed.
    var frames = [Float](repeating: 0, count: T * n)
    for t in 0..<T {
        let off = t * hop
        for j in 0..<n { frames[t * n + j] = x[off + j] * fe.hann[j] }
    }
    // Real/Imag = frames[T,n] · basis[n,freqs]  (BLAS), then power = re²+im².
    // vDSP_mmul: C[M×N] = A[M×P]·B[P×N], row-major. Non-deprecated Accelerate matmul.
    var re = [Float](repeating: 0, count: T * freqs)
    var im = [Float](repeating: 0, count: T * freqs)
    fe.cosB.withUnsafeBufferPointer { cb in
        frames.withUnsafeBufferPointer { fb in
            vDSP_mmul(fb.baseAddress!, 1, cb.baseAddress!, 1, &re, 1,
                      vDSP_Length(T), vDSP_Length(freqs), vDSP_Length(n))
        }
    }
    fe.sinB.withUnsafeBufferPointer { sb in
        frames.withUnsafeBufferPointer { fb in
            vDSP_mmul(fb.baseAddress!, 1, sb.baseAddress!, 1, &im, 1,
                      vDSP_Length(T), vDSP_Length(freqs), vDSP_Length(n))
        }
    }
    var power = [Float](repeating: 0, count: T * freqs)
    for i in 0..<(T * freqs) { power[i] = re[i] * re[i] + im[i] * im[i] }

    // mel = power[T,freqs] · melFB[freqs,mels]
    var mel = [Float](repeating: 0, count: T * mels)
    fe.melFB.withUnsafeBufferPointer { mb in
        power.withUnsafeBufferPointer { pb in
            vDSP_mmul(pb.baseAddress!, 1, mb.baseAddress!, 1, &mel, 1,
                      vDSP_Length(T), vDSP_Length(mels), vDSP_Length(freqs))
        }
    }
    // AmplitudeToDB(power, top_db=80): 10·log10(max(x,1e-10)), clamp to global max-80.
    var maxDB: Float = -.greatestFiniteMagnitude
    for i in 0..<mel.count {
        let db = 10.0 * log10(max(mel[i], 1e-10))
        mel[i] = db
        if db > maxDB { maxDB = db }
    }
    let floor = maxDB - 80.0
    // dB clamp + fixed normalization, in one pass.
    for i in 0..<mel.count {
        let v = max(mel[i], floor)
        mel[i] = (v - Spec.melMean) / Spec.melStd
    }
    return (mel, T)   // mel is [T, mels] row-major
}

// MARK: - Inference

/// Fill an MLMultiArray with one transposed mel chunk and wrap it as a feature provider.
func makeProvider(_ arr: MLMultiArray, mel: [Float], f0: Int, mels: Int, cf: Int) throws -> MLFeatureProvider {
    let ptr = arr.dataPointer.assumingMemoryBound(to: Float.self)
    for m in 0..<mels {
        for fr in 0..<cf {
            ptr[m * cf + fr] = mel[(f0 + fr) * mels + m]
        }
    }
    return try MLDictionaryFeatureProvider(dictionary: ["chunk": arr])
}

func predictProbs(modelURL: URL, mel: [Float], frames T: Int) -> (probs: [Double], centers: [Double]) {
    let mels = Spec.nMels, cf = Spec.chunkFrames, chop = Spec.chunkHopFrames
    let cfg = MLModelConfiguration()
    // MLModel needs a *compiled* model. Accept a ready .mlmodelc, else compile the
    // .mlmodel (the app can pre-compile after download to skip this per run).
    let compiled: URL
    if modelURL.pathExtension == "mlmodelc" {
        compiled = modelURL
    } else if let c = try? MLModel.compileModel(at: modelURL) {
        compiled = c
    } else {
        fail("could not compile model at \(modelURL.path)")
    }
    guard let model = try? MLModel(contentsOf: compiled, configuration: cfg) else {
        fail("could not load model at \(compiled.path)")
    }
    // Build all chunk inputs [1,1,nMels,chunkFrames] (mel is [T, mels] → transpose slice).
    var providers: [MLFeatureProvider] = []
    var centers: [Double] = []
    var f0 = 0
    while f0 + cf <= T {
        guard let arr = try? MLMultiArray(shape: [1, 1, NSNumber(value: mels), NSNumber(value: cf)],
                                          dataType: .float32),
              let provider = try? makeProvider(arr, mel: mel, f0: f0, mels: mels, cf: cf) else {
            fail("could not build model input")
        }
        providers.append(provider)
        centers.append((Double(f0) + Double(cf) / 2.0) * Spec.frameSec)
        f0 += chop
    }
    guard !providers.isEmpty else { return ([], []) }
    let batch = MLArrayBatchProvider(array: providers)
    guard let out = try? model.predictions(fromBatch: batch) else { fail("model inference failed") }
    var probs = [Double](repeating: 0, count: out.count)
    for i in 0..<out.count {
        let fv = out.features(at: i).featureValue(for: "filler_prob")
        probs[i] = fv?.multiArrayValue?[0].doubleValue ?? fv?.doubleValue ?? 0
    }
    return (probs, centers)
}

// MARK: - Threshold + merge  (mirrors infer.predict_intervals)

func intervals(probs: [Double], centers: [Double], threshold: Double) -> [[Double]] {
    let half = Spec.chunkSec / 2.0
    var runs: [[Double]] = []
    var cur: [Double]?
    for i in 0..<centers.count {
        if probs[i] >= threshold {
            if cur == nil {
                cur = [centers[i] - half, centers[i] + half]
            } else {
                cur![1] = centers[i] + half
            }
        } else if cur != nil {
            runs.append(cur!)
            cur = nil
        }
    }
    if let c = cur { runs.append(c) }
    var merged: [[Double]] = []
    for r in runs {
        if var last = merged.last, r[0] - last[1] <= Spec.mergeGap {
            last[1] = r[1]; merged[merged.count - 1] = last
        } else { merged.append(r) }
    }
    return merged.filter { $0[1] - $0[0] >= Spec.minFiller }
        .map { [($0[0] * 1000).rounded() / 1000, ($0[1] * 1000).rounded() / 1000] }
}

// MARK: - main

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("crisp-filler: \(msg)\n".utf8))
    exit(1)
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

guard let modelPath = arg("--model"), let audioPath = arg("--audio") else {
    fail("usage: crisp-filler --model <model.mlmodel> --audio <in.wav> [--config <model.config.json>] [--threshold N]")
}
// Layered config: built-in defaults ← model's config.json ← explicit --threshold.
if let cfg = arg("--config") { Spec.load(cfg) }
let threshold = arg("--threshold").flatMap(Double.init) ?? Spec.defaultThreshold

let signal = readWav(audioPath)
let fe = Frontend()
let (mel, T) = logMel(signal, fe)
let (probs, centers) = predictProbs(modelURL: URL(fileURLWithPath: modelPath), mel: mel, frames: T)
let fillers = intervals(probs: probs, centers: centers, threshold: threshold)

guard let json = try? JSONSerialization.data(withJSONObject: ["fillers": fillers], options: []) else {
    fail("could not encode output")
}
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
