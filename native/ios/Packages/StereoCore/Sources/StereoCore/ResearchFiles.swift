import Foundation

public enum ResearchError: Error, LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        }
    }
}

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func unsignedLE(_ offset: Int, bytes: Int) throws -> UInt64 {
        guard offset >= 0, bytes > 0, bytes <= 8, offset + bytes <= count else {
            throw ResearchError.invalid("잘린 바이너리 파일입니다.")
        }
        return (0..<bytes).reduce(0) { $0 | UInt64(self[offset + $1]) << ($1 * 8) }
    }
}

/// Portable SHA-256 file checksum. Verified against hashlib and standard vectors.
public struct ResearchSHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
    ]
    private var words: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
    private var tail = [UInt8]()
    private var length: UInt64 = 0

    public init() {}

    public mutating func update(_ data: Data) {
        length += UInt64(data.count)
        let bytes = tail + Array(data)
        let end = bytes.count / 64 * 64
        for offset in stride(from: 0, to: end, by: 64) {
            compress(Array(bytes[offset..<(offset + 64)]))
        }
        tail = Array(bytes[end...])
    }

    public func hexDigest() -> String {
        var copy = self
        var padding = Data([0x80])
        while (copy.tail.count + padding.count) % 64 != 56 { padding.append(0) }
        let bits = length * 8
        for shift in stride(from: 56, through: 0, by: -8) { padding.append(UInt8(truncatingIfNeeded: bits >> shift)) }
        copy.update(padding)
        return copy.words.map { String(format: "%08x", $0) }.joined()
    }

    public static func file(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = Self()
        while let data = try handle.read(upToCount: 65536), !data.isEmpty { hash.update(data) }
        return hash.hexDigest()
    }

    private func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

    private mutating func compress(_ bytes: [UInt8]) {
        var schedule = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            for j in 0..<4 { schedule[i] = (schedule[i] << 8) | UInt32(bytes[i * 4 + j]) }
        }
        for i in 16..<64 {
            let x = schedule[i - 15]
            let y = schedule[i - 2]
            let s0 = rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3)
            let s1 = rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10)
            schedule[i] = schedule[i - 16] &+ s0 &+ schedule[i - 7] &+ s1
        }
        var v = words
        for i in 0..<64 {
            let s1 = rotate(v[4], 6) ^ rotate(v[4], 11) ^ rotate(v[4], 25)
            let choose = (v[4] & v[5]) ^ (~v[4] & v[6])
            let t1 = v[7] &+ s1 &+ choose &+ Self.constants[i] &+ schedule[i]
            let s0 = rotate(v[0], 2) ^ rotate(v[0], 13) ^ rotate(v[0], 22)
            let majority = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
            v = [t1 &+ s0 &+ majority, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
        }
        for i in 0..<8 { words[i] = words[i] &+ v[i] }
    }
}

public final class FloatWAVWriter {
    public let channels: Int
    public let sampleRate: Int
    public private(set) var frames = 0
    private var handle: FileHandle?

    public init(url: URL, channels: Int, sampleRate: Int) throws {
        guard [2,4].contains(channels), (32000...96000).contains(sampleRate),
              FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw ResearchError.invalid("WAV 파일을 만들 수 없습니다.")
        }
        self.channels = channels
        self.sampleRate = sampleRate
        handle = try FileHandle(forWritingTo: url)
        try handle?.write(contentsOf: header(frames: 0))
    }

    public func append(_ pcm: [[Float]]) throws {
        guard let handle, pcm.count == channels, let count = pcm.first?.count,
              count > 0, count <= 16384,
              pcm.allSatisfy({ $0.count == count && $0.allSatisfy(\.isFinite) }),
              frames + count <= sampleRate * 120 else {
            throw ResearchError.invalid("WAV 입력 불일치 또는 연구 녹음 120초 한도입니다.")
        }
        var data = Data(capacity: count * channels * 4)
        for i in 0..<count {
            for channel in pcm { data.appendLE(channel[i].bitPattern) }
        }
        try handle.write(contentsOf: data)
        frames += count
    }

    public func finish() throws {
        guard let file = handle else { return }
        handle = nil
        defer { try? file.close() }
        try file.seek(toOffset: 0)
        try file.write(contentsOf: header(frames: frames))
        try file.synchronize()
    }

    deinit { try? handle?.close() }

    private func header(frames: Int) -> Data {
        let size = UInt32(frames * channels * 4)
        var data = Data("RIFF".utf8)
        data.appendLE(size + 48)
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(3))
        data.appendLE(UInt16(channels))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * channels * 4))
        data.appendLE(UInt16(channels * 4))
        data.appendLE(UInt16(32))
        data.append(contentsOf: "fact".utf8)
        data.appendLE(UInt32(4))
        data.appendLE(UInt32(frames))
        data.append(contentsOf: "data".utf8)
        data.appendLE(size)
        return data
    }
}

public final class FloatWAVReader {
    public let channels: Int
    public let sampleRate: Int
    public let frames: Int
    private let handle: FileHandle
    private let dataOffset: UInt64

    public init(url: URL) throws {
        let file = try FileHandle(forReadingFrom: url)
        do {
            let size = try file.seekToEnd()
            try file.seek(toOffset: 0)
            let header = try file.read(upToCount: 12) ?? Data()
            guard header.count == 12, String(data: header.prefix(4), encoding: .ascii) == "RIFF",
                  String(data: header.suffix(4), encoding: .ascii) == "WAVE",
                  try header.unsignedLE(4, bytes: 4) + 8 == size else {
                throw ResearchError.invalid("완성된 RIFF WAV 파일이 아닙니다.")
            }
            var channelCount: Int?
            var rate: Int?
            var audio: (UInt64, Int)?
            var offset: UInt64 = 12
            while offset + 8 <= size {
                try file.seek(toOffset: offset)
                let chunk = try file.read(upToCount: 8) ?? Data()
                let count = try chunk.unsignedLE(4, bytes: 4)
                guard offset + 8 + count <= size else { throw ResearchError.invalid("잘린 WAV chunk입니다.") }
                let name = String(data: chunk.prefix(4), encoding: .ascii)
                if name == "fmt " {
                    guard count == 16 else { throw ResearchError.invalid("연구 Float32 WAV 형식만 지원합니다.") }
                    let format = try file.read(upToCount: 16) ?? Data()
                    let c = Int(try format.unsignedLE(2, bytes: 2))
                    let r = Int(try format.unsignedLE(4, bytes: 4))
                    guard try format.unsignedLE(0, bytes: 2) == 3,
                          try format.unsignedLE(14, bytes: 2) == 32,
                          [2,4].contains(c), (32000...96000).contains(r),
                          try format.unsignedLE(12, bytes: 2) == UInt64(c * 4),
                          try format.unsignedLE(8, bytes: 4) == UInt64(r * c * 4) else {
                        throw ResearchError.invalid("WAV 형식이 Float32 연구 계약과 다릅니다.")
                    }
                    channelCount = c
                    rate = r
                } else if name == "data" {
                    guard audio == nil else { throw ResearchError.invalid("중복 WAV data chunk입니다.") }
                    audio = (offset + 8, Int(count))
                }
                offset += 8 + count + count % 2
            }
            guard let c = channelCount, let r = rate, let audio,
                  audio.1 % (c * 4) == 0, audio.1 / (c * 4) <= r * 120 else {
                throw ResearchError.invalid("WAV 채널·샘플 수를 확인할 수 없습니다.")
            }
            channels = c
            sampleRate = r
            frames = audio.1 / (c * 4)
            dataOffset = audio.0
            handle = file
        } catch {
            try? file.close()
            throw error
        }
    }

    public func read(at start: Int, count: Int) throws -> [[Float]] {
        guard start >= 0, count > 0, count <= 16384, start + count <= frames else {
            throw ResearchError.invalid("WAV 읽기 범위를 벗어났습니다.")
        }
        try handle.seek(toOffset: dataOffset + UInt64(start * channels * 4))
        let data = try handle.read(upToCount: count * channels * 4) ?? Data()
        var result = Array(repeating: [Float](), count: channels)
        for i in 0..<count {
            for c in 0..<channels {
                let value = Float(bitPattern: UInt32(try data.unsignedLE((i * channels + c) * 4, bytes: 4)))
                guard value.isFinite else { throw ResearchError.invalid("WAV에 비유한 PCM이 있습니다.") }
                result[c].append(value)
            }
        }
        return result
    }

    deinit { try? handle.close() }
}
