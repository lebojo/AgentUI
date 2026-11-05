extension Collection<UInt8> {
    var isTerminalFocusReport: Bool {
        elementsEqual([0x1b, 0x5b, 0x49]) || elementsEqual([0x1b, 0x5b, 0x4f])
    }

    var isTerminalMouseMotionReport: Bool {
        (mouseReportButtonFlags ?? 0) & 32 != 0
    }

    private var mouseReportButtonFlags: Int? {
        guard (6...32).contains(count) else { return nil }
        let bytes = Array(self)
        guard bytes.starts(with: [0x1b, 0x5b]), let final = bytes.last else { return nil }
        if bytes[2] == UInt8(ascii: "M") { return Int(bytes[3]) - 32 }
        let isSGR = bytes[2] == UInt8(ascii: "<")
        let parameters = bytes[(isSGR ? 3 : 2)..<(bytes.count - 1)].split(separator: UInt8(ascii: ";"))
        guard final == UInt8(ascii: "M") || (isSGR && final == UInt8(ascii: "m")), parameters.count == 3,
              parameters.allSatisfy({ $0.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) } }),
              let flags = Int(String(decoding: parameters[0], as: UTF8.self)) else { return nil }
        return isSGR ? flags : flags - 32
    }
}
