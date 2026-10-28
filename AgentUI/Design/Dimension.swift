import CoreGraphics

enum Dimension {
    enum Window {
        static let defaultWidth: CGFloat = 1180
        static let defaultHeight: CGFloat = 760
        static let minWidth: CGFloat = 760
        static let minHeight: CGFloat = 480
    }

    enum Sidebar {
        static let minWidth: CGFloat = 240
        static let idealWidth: CGFloat = 285
        static let maxWidth: CGFloat = 420
    }

    enum Inspector {
        static let minWidth: CGFloat = 260
        static let idealWidth: CGFloat = 310
        static let maxWidth: CGFloat = 440
        static let statusColumnWidth: CGFloat = 22
    }

    enum Detail {
        static let headerHeight: CGFloat = 40
        static let footerHeight: CGFloat = 29
    }

    enum Badge {
        static let sidebarMaxWidth: CGFloat = 100
        static let detailMaxWidth: CGFloat = 180
    }

    enum Sheet {
        static let width: CGFloat = 440
    }

    enum PreviewSheet {
        static let minWidth: CGFloat = 560
        static let idealWidth: CGFloat = 780
        static let minHeight: CGFloat = 360
        static let idealHeight: CGFloat = 540
    }

    enum Settings {
        static let width: CGFloat = 580
        static let minHeight: CGFloat = 460
        static let idealHeight: CGFloat = 640
        static let themeCardMinWidth: CGFloat = 112
        static let themeSampleHeight: CGFloat = 52
        static let swatchSize: CGFloat = 8
    }

    enum DiffSheet {
        static let idealWidth: CGFloat = 1000
        static let idealHeight: CGFloat = 640
        static let markerWidth: CGFloat = 14
    }

    enum Usage {
        static let percentMinWidth: CGFloat = 30
    }
}
