import Foundation

/// ZIP STORE writer. Streams entries, caps classic ZIP sizes and never changes sources.
enum MotionArchive {
    private static let table:[UInt32]=(0..<256).map{value in
        var crc=UInt32(value)
        for _ in 0..<8 {crc=crc & 1 == 1 ? 0xedb88320 ^ (crc >> 1):crc >> 1}
        return crc
    }
    private static func checksum(_ url:URL)throws->(UInt32,UInt32) {
        let input=try FileHandle(forReadingFrom:url);defer{try? input.close()}
        var crc:UInt32=0xffffffff;var size:UInt64=0
        while let data=try input.read(upToCount:65536),!data.isEmpty {
            size+=UInt64(data.count)
            guard size<=UInt64(UInt32.max) else {throw CocoaError(.fileWriteOutOfSpace)}
            for byte in data {crc=table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8)}
        }
        return(crc ^ 0xffffffff,UInt32(size))
    }
    private static func u16(_ v:UInt16)->Data {Data([UInt8(v & 255),UInt8(v >> 8)])}
    private static func u32(_ v:UInt32)->Data {Data([UInt8(v & 255),UInt8((v >> 8)&255),UInt8((v >> 16)&255),UInt8(v >> 24)])}
    static func write(files:[String:URL],to destination:URL)throws {
        guard files.count<=65535 else{throw CocoaError(.fileWriteOutOfSpace)}
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString+".zip")
        guard FileManager.default.createFile(atPath:temporary.path,contents:nil) else {throw CocoaError(.fileWriteUnknown)}
        defer{try? FileManager.default.removeItem(at:temporary)}
        let output=try FileHandle(forWritingTo:temporary);defer{try? output.close()}
        var central=Data();var offset:UInt32=0
        for name in files.keys.sorted() {
            guard !name.contains("/"),!name.contains("\\"),name != ".",name != "..",!name.isEmpty else{throw CocoaError(.fileWriteInvalidFileName)}
            let encoded=Data(name.utf8);guard encoded.count<=65535 else{throw CocoaError(.fileWriteInvalidFileName)}
            let url=files[name]!;let(crc,size)=try checksum(url);let length=UInt16(encoded.count)
            let header=u32(0x04034b50)+u16(20)+u16(0x0800)+u16(0)+u16(0)+u16(0x21)+u32(crc)+u32(size)+u32(size)+u16(length)+u16(0)+encoded
            try output.write(contentsOf:header)
            let input=try FileHandle(forReadingFrom:url)
            do{while let data=try input.read(upToCount:65536),!data.isEmpty{try output.write(contentsOf:data)};try input.close()}catch{try? input.close();throw error}
            central += u32(0x02014b50)+u16(20)+u16(20)+u16(0x0800)
            central += u16(0)+u16(0)+u16(0x21)+u32(crc)
            central += u32(size)+u32(size)+u16(length)+u16(0)
            central += u16(0)+u16(0)+u16(0)+u32(0)+u32(offset)+encoded
            let next=UInt64(offset)+UInt64(header.count)+UInt64(size)
            guard next<=UInt64(UInt32.max) else{throw CocoaError(.fileWriteOutOfSpace)};offset=UInt32(next)
        }
        guard central.count<=Int(UInt32.max) else{throw CocoaError(.fileWriteOutOfSpace)}
        try output.write(contentsOf:central)
        try output.write(contentsOf:u32(0x06054b50)+u16(0)+u16(0)+u16(UInt16(files.count))+u16(UInt16(files.count))+u32(UInt32(central.count))+u32(offset)+u16(0))
        try output.synchronize();try output.close()
        // Export names are unique to this invocation, so no destructive replacement is needed.
        try FileManager.default.moveItem(at:temporary,to:destination)
    }
    static func csvCell(_ value:String)->String {"\""+value.replacingOccurrences(of:"\"",with:"\"\"")+"\""}
}
