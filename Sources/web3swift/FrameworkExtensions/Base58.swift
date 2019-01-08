//
//  Base58.swift
//  web3swift
//
//  Created by Alexander Vlasov on 10.01.2018.
//  Copyright © 2018 Bankex Foundation. All rights reserved.
//

import Foundation
import base58

enum Base58Alphabet: Int8 {
    case bitcoin, ripple
}

extension Data {
    func base58(_ type: Base58Alphabet) -> String {
        let input = withUnsafeBytes { UnsafeRawPointer($0) }
        var size = count*2
        var data = Data(count: size)
        let output: UnsafeMutablePointer<Int8> = data.withUnsafeMutableBytes { return $0 }
        b58enc(output, &size, input, count, type.rawValue)
        return String(data: data[..<size], encoding: .utf8)!
    }
    func base58Check(_ type: Base58Alphabet, _ prefix: UInt8) -> String {
        let input = withUnsafeBytes { UnsafeRawPointer($0) }
        var size = count*2
        var data = Data(count: size)
        let output: UnsafeMutablePointer<Int8> = data.withUnsafeMutableBytes { return $0 }
        
        b58check_enc(output, &size, prefix, input, count, type.rawValue)
        return String(data: data[..<size], encoding: .utf8)!
    }
}
extension String {
    func base58(_ type: Base58Alphabet) -> Data? {
        let data = Data(utf8)
        let string: UnsafePointer<Int8> = data.withUnsafeBytes { $0 }
        var result = Data(count: count)
        var size = count
        b58tobin(result.mutablePointer(), &size, string, data.count, type.rawValue)
        return result.subdata(in: count-size..<count)
    }
    func base58Check(_ type: Base58Alphabet) -> Data? {
        let data = Data(utf8)
        let string: UnsafePointer<Int8> = data.withUnsafeBytes { $0 }
        var result = Data(count: count)
        var size = 0
        let g = b58check(&result, size, string, data.count, 0x21)
//        b58tobin(&result, &size, string, data.count, type.rawValue)
        return Data(result[..<size])
    }
}

struct Base58 {
    static let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    // Encode
    static func base58FromBytes(_ bytes: [UInt8]) -> String {
        var bytes = bytes
        var zerosCount = 0
        var length = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        let size = bytes.count * 138 / 100 + 1

        var base58: [UInt8] = Array(repeating: 0, count: size)
        for b in bytes {
            var carry = Int(b)
            var i = 0

            for j in 0 ... base58.count - 1 where carry != 0 || i < length {
                carry += 256 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }

            assert(carry == 0)

            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0
        var str = ""
        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        base58.removeFirst(zerosToRemove)

        while 0 < zerosCount {
            str = "\(str)1"
            zerosCount -= 1
        }

        for b in base58 {
            str = "\(str)\(base58Alphabet[String.Index(encodedOffset: Int(b))])"
        }

        return str
    }

    // Decode
    static func bytesFromBase58(_ base58: String) -> [UInt8] {
        // remove leading and trailing whitespaces
        let string = base58.trimmingCharacters(in: CharacterSet.whitespaces)

        guard !string.isEmpty else { return [] }

        var zerosCount = 0
        var length = 0
        for c in string {
            if c != "1" { break }
            zerosCount += 1
        }

        let size = string.lengthOfBytes(using: String.Encoding.utf8) * 733 / 1000 + 1 - zerosCount
        var base58: [UInt8] = Array(repeating: 0, count: size)
        for c in string where c != " " {
            // search for base58 character
            guard let base58Index = base58Alphabet.index(of: c) else { return [] }

            var carry = base58Index.encodedOffset
            var i = 0
            for j in 0 ... base58.count where carry != 0 || i < length {
                carry += 58 * Int(base58[base58.count - j - 1])
                base58[base58.count - j - 1] = UInt8(carry % 256)
                carry /= 256
                i += 1
            }

            assert(carry == 0)
            length = i
        }

        // skip leading zeros
        var zerosToRemove = 0

        for b in base58 {
            if b != 0 { break }
            zerosToRemove += 1
        }
        
        base58.replaceSubrange(..<zerosToRemove, with: Array(repeating: 0, count: zerosCount))
        return base58
    }
}

extension Array where Element == UInt8 {
    /**
     - Returns: base58 encoded string from byte array
     */
    public var base58EncodedString: String {
        guard !isEmpty else { return "" }
        return Base58.base58FromBytes(self)
    }
    
    /**
     - Returns: base58 encoded string with checksum its hash at the end
     */
    public var base58CheckEncodedString: String {
        var bytes = self
        bytes.append(contentsOf: Array(Data(self).sha256().sha256()[0..<4]))

        return Base58.base58FromBytes(bytes)
    }
}

extension String {
    /**
     - Returns: base 58 encoded string of its utf8 representation
    */
    public var base58EncodedString: String {
        return [UInt8](utf8).base58EncodedString
    }

    /**
     - Returns: data converted from base58 string
     */
    public var base58DecodedData: Data? {
        let bytes = Base58.bytesFromBase58(self)
        return Data(bytes)
    }

    /**
     - Returns: data converted from base58 string encoded with hash
     */
    public var base58CheckDecodedData: Data? {
        guard let bytes = self.base58CheckDecodedBytes else { return nil }
        return Data(bytes)
    }

    
    /**
     - Returns: data converted from base58 string encoded with hash
     */
    public var base58CheckDecodedBytes: [UInt8]? {
        var bytes = Base58.bytesFromBase58(self)
        guard 4 <= bytes.count else { return nil }

        let checksum = [UInt8](bytes[bytes.count - 4 ..< bytes.count])
        bytes = [UInt8](bytes[0 ..< bytes.count - 4])

        let calculatedChecksum = Array(Data(bytes).sha256().sha256()[0..<4])
        if checksum != calculatedChecksum { return nil }

        return bytes
    }

//    public var littleEndianHexToUInt: UInt {
//        let data = Data.fromHex(self)!
//        let revensed =
//        return UInt(sel)
//        return UInt(self.dataWithHexString().bytes.reversed().fullHexString,radix: 16)!
//    }
}