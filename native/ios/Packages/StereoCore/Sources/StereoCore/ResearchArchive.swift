import Foundation

/// Store-only ZIP with bounded memory. The shared file contains a complete session,
/// never camera imagery. The final name appears only after a successful close.
public enum ResearchArchive {
    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        return crc
    }

    public static func create(folder: URL, destination: URL) throws {
        let manifest = try JSONDecoder().decode(ResearchManifest.self,
            from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        try ResearchReplay.validate(manifest, folder: folder)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw ResearchError.invalid("연구 ZIP 파일을 만들 수 없습니다.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var central = Data()
        var offset: UInt32 = 0
        let names = ["manifest.json"] + manifest.files.map(\.name)
        for name in names {
            let input = try FileHandle(forReadingFrom: folder.appendingPathComponent(name))
            defer { try? input.close() }
            var crc: UInt32 = 0xffffffff
            var length: UInt32 = 0
            while let block = try input.read(upToCount: 65536), !block.isEmpty {
                for byte in block { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
                length += UInt32(block.count)
            }
            crc ^= 0xffffffff
            let filename = Data(name.utf8)
            var header = Data()
            header.appendLE(UInt32(0x04034b50))
            header.appendLE(UInt16(20))
            header.appendLE(UInt16(0))
            header.appendLE(UInt16(0))
            header.appendLE(UInt16(0))
            header.appendLE(UInt16(33)) // 1980-01-01; precise UTC is in manifest.
            header.appendLE(crc)
            header.appendLE(length)
            header.appendLE(length)
            header.appendLE(UInt16(filename.count))
            header.appendLE(UInt16(0))
            header.append(filename)
            try output.write(contentsOf: header)
            try input.seek(toOffset: 0)
            while let block = try input.read(upToCount: 65536), !block.isEmpty { try output.write(contentsOf: block) }
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))
            central.append(header.subdata(in: 4..<28))
            central.appendLE(UInt16(0)) // extra
            central.appendLE(UInt16(0)) // comment
            central.appendLE(UInt16(0)) // disk
            central.appendLE(UInt16(0)) // internal attributes
            central.appendLE(UInt32(0))
            central.appendLE(offset)
            central.append(filename)
            offset += UInt32(header.count) + length
        }
        try output.write(contentsOf: central)
        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(names.count))
        end.appendLE(UInt16(names.count))
        end.appendLE(UInt32(central.count))
        end.appendLE(offset)
        end.appendLE(UInt16(0))
        try output.write(contentsOf: end)
        try output.synchronize()
        try output.close()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
