extension Optional {
    var isPresent: Bool {
        get { self != nil }
        set { if !newValue { self = nil } }
    }
}
