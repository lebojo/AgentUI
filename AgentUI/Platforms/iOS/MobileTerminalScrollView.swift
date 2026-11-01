import UIKit
import SwiftTerm

final class MobileTerminalScrollView: UIScrollView, UIScrollViewDelegate {
    private let canvas = UIView()
    private let terminal: TerminalView
    private var canvasSize = CGSize.zero
    private var lastViewport = CGSize.zero
    private var followsFit = true
    private var fitting = false

    init(terminal: TerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        delegate = self
        maximumZoomScale = 3
        minimumZoomScale = 0.1
        contentInsetAdjustmentBehavior = .never
        keyboardDismissMode = .interactive
        backgroundColor = terminal.layer.backgroundColor.map { UIColor(cgColor: $0) } ?? terminal.nativeBackgroundColor
        canvas.backgroundColor = backgroundColor
        canvas.addSubview(terminal)
        addSubview(canvas)
        let reset = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 2
        addGestureRecognizer(reset)
        accessibilityLabel = String(localized: "Terminal Screen")
        accessibilityHint = String(localized: "Pinch to zoom. Double-tap with two fingers to fit the width.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setCanvasSize(_ size: CGSize) {
        guard size != canvasSize, size.width > 0, size.height > 0 else { return }
        canvasSize = size
        fitting = true
        setZoomScale(1, animated: false)
        canvas.frame = CGRect(origin: .zero, size: size)
        terminal.frame = canvas.bounds
        contentSize = size
        fitting = false
        followsFit = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard canvasSize.width > 0, bounds.width > 0 else { return }
        let scale = min(1, bounds.width / canvasSize.width)
        if bounds.size != lastViewport || abs(minimumZoomScale - scale) > 0.001 {
            lastViewport = bounds.size
            fitting = true
            minimumZoomScale = scale
            if followsFit { setZoomScale(scale, animated: false) }
            fitting = false
        } else if followsFit, abs(zoomScale - scale) > 0.001 {
            fitting = true
            setZoomScale(scale, animated: false)
            fitting = false
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { followsFit = false }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        if !fitting { followsFit = abs(zoomScale - minimumZoomScale) < 0.01 }
    }
    @objc private func resetZoom() { followsFit = true; setNeedsLayout() }
}
