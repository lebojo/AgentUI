extension Collection<UInt8> {
    var isTerminalFocusReport: Bool {
        elementsEqual([0x1b, 0x5b, 0x49]) || elementsEqual([0x1b, 0x5b, 0x4f])
    }
}
