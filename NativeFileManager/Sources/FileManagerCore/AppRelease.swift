import Foundation
import CryptoKit

public struct ReleaseVersion:Comparable,Equatable,Sendable {
    public let components:[Int]
    public init(_ value:String) throws {
        let fields=value.split(separator:".",omittingEmptySubsequences:false)
        guard (2...3).contains(fields.count),fields.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber)}),fields.allSatisfy({Int($0) != nil}) else {throw UpdateError.invalid("版本号格式不正确")}
        components=fields.map{Int($0)!}+Array(repeating:0,count:3-fields.count)
    }
    public static func <(a:Self,b:Self)->Bool {a.components.lexicographicallyPrecedes(b.components)}
}
public enum UpdateError:LocalizedError {
    case invalid(String)
    public var errorDescription:String? {switch self {case .invalid(let message):return message}}
}
public struct AppRelease:Codable,Sendable {
    public let version:String
    public let build:Int
    public let minimumSystemVersion:String
    public let architecture:String
    public let downloadURL:URL
    public let sha256:String
    public let bytes:Int64
    public let notes:[String]
    public init(version:String,build:Int,minimumSystemVersion:String,architecture:String,downloadURL:URL,sha256:String,bytes:Int64,notes:[String]) {
        self.version=version;self.build=build;self.minimumSystemVersion=minimumSystemVersion;self.architecture=architecture;self.downloadURL=downloadURL;self.sha256=sha256;self.bytes=bytes;self.notes=notes
    }
    public func validate() throws {
        _ = try ReleaseVersion(version);_ = try ReleaseVersion(minimumSystemVersion)
        guard build>0,architecture == "arm64",bytes>0,bytes<=512*1024*1024,
              sha256.count == 64,sha256.allSatisfy({$0.isHexDigit}),
              Self.allowed(downloadURL),downloadURL.path == "/Octo-\(version)-macos-arm64.zip" else {throw UpdateError.invalid("更新信息校验失败")}
    }
    public static func allowed(_ url:URL)->Bool {url.scheme == "https" && url.host == "octo-dl.xiezhaoye.site" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)}
    public func isNewer(than version:String,build currentBuild:Int) throws ->Bool {
        let candidate=try ReleaseVersion(self.version),current=try ReleaseVersion(version)
        return candidate>current || (candidate == current && build>currentBuild)
    }
    public static func supportsArm64Executable(_ data:Data)->Bool {
        func be32(_ offset:Int)->UInt32? {guard offset>=0,offset+4<=data.count else{return nil};return data[offset..<offset+4].reduce(UInt32(0)){($0<<8)|UInt32($1)}}
        guard data.count>=8 else{return false}
        if Array(data.prefix(4)) == [0xcf,0xfa,0xed,0xfe] {return Array(data[4..<8]) == [0x0c,0,0,1]}
        guard let magic=be32(0),[UInt32(0xcafebabe),0xcafebabf].contains(magic),let count=be32(4),count>0,count<32 else{return false}
        let stride=magic == 0xcafebabe ? 20:32
        return (0..<Int(count)).contains{be32(8+$0*stride) == 0x0100000c}
    }
    public func verify(_ archive:URL) throws {
        let data=try Data(contentsOf:archive,options:.mappedIfSafe)
        guard data.count == bytes,SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == sha256.lowercased() else {throw UpdateError.invalid("安装包大小或 SHA-256 不匹配，已停止安装")}
        try UpdateArchive.inspect(data)
    }
}

/// Inspect the ZIP central directory before extraction. Updates contain one real app,
/// no symlinks, path traversal, encryption, ZIP64 or unbounded expanded payloads.
public enum UpdateArchive {
    public static func inspect(_ data:Data) throws {
        func fail() -> UpdateError { .invalid("更新 ZIP 结构或路径不符合要求") }
        func u16(_ offset:Int)throws->Int {guard offset>=0,offset+2<=data.count else{throw fail()};return Int(data[offset]) | Int(data[offset+1])<<8}
        func u32(_ offset:Int)throws->Int {try u16(offset) | u16(offset+2)<<16}
        guard data.count>=22 else{throw fail()}
        var eocd:Int?
        for i in stride(from:data.count-22,through:max(0,data.count-65557),by:-1) {
            if try u32(i) == 0x06054b50,try i+22+u16(i+20) == data.count {eocd=i;break}
        }
        guard let end=eocd,try u16(end+4)==0,try u16(end+6)==0 else{throw fail()}
        let count=try u16(end+10),start=try u32(end+16),length=try u32(end+12)
        guard count>0,count<20000,try u16(end+8)==count,start+length==end else{throw fail()}
        var cursor=start,total=0,executables=0
        var names=Set<String>()
        for _ in 0..<count {
            guard try u32(cursor)==0x02014b50 else{throw fail()}
            let flags=try u16(cursor+8),method=try u16(cursor+10),size=try u32(cursor+24),compressed=try u32(cursor+20)
            let nameLength=try u16(cursor+28),extra=try u16(cursor+30),comment=try u16(cursor+32),local=try u32(cursor+42),attributes=try u32(cursor+38)
            let next=cursor+46+nameLength+extra+comment
            guard next<=end,flags&1==0,[0,8].contains(method),size<1_073_741_824,compressed<1_073_741_824,
                  (attributes>>16)&0xf000 != 0xa000,
                  let name=String(data:data[(cursor+46)..<(cursor+46+nameLength)],encoding:.utf8),
                  !name.contains("\\"),!name.contains("\0"),!name.hasPrefix("/"),
                  !name.split(separator:"/",omittingEmptySubsequences:false).contains(".."),names.insert(name).inserted,
                  name.hasPrefix("Octo.app/") || name == "Octo.app" || name.hasPrefix("__MACOSX/"),
                  try u32(local)==0x04034b50,try u16(local+26)==nameLength else{throw fail()}
            let localExtra=try u16(local+28),payload=local+30+nameLength+localExtra
            guard payload+compressed<=start,local+30+nameLength<=data.count,
                  data[(local+30)..<(local+30+nameLength)] == data[(cursor+46)..<(cursor+46+nameLength)] else{throw fail()}
            total+=size;guard total<=1_073_741_824 else{throw fail()}
            if name == "Octo.app/Contents/MacOS/DualPane" {executables+=1}
            cursor=next
        }
        guard cursor==end,executables==1 else{throw fail()}
    }
}
