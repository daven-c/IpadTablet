import UIKit
import SwiftUI
import Network

/// Turns the iPad screen into a blank absolute-position digitizer: Apple Pencil
/// contact is tracked at hardware coalesced-touch resolution and streamed as
/// normalized (0.0-1.0) coordinates over a TCP socket that the Mac reaches
/// through `iproxy`'s usbmuxd tunnel over the USB cable — no Wi-Fi involved,
/// which matters on a Wi-Fi-only iPad with no Personal Hotspot.
final class DigitizerViewController: UIViewController {
    private let port: NWEndpoint.Port = 12345
    private var listener: NWListener?
    private var connection: NWConnection?

    private let statusLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)
    private let activeAreaOutline = CAShapeLayer()
    private var activeRect: CGRect = .zero
    private var smoothingAlpha: Float = 1.0
    private var smoothedX: Float?
    private var smoothedY: Float?

    private var isDraggingActiveArea = false
    private var dragStartRect: CGRect = .zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = false
        overrideUserInterfaceStyle = .dark

        setUpStatusLabel()
        setUpSettingsButton()
        setUpLockButton()
        setUpActiveAreaOutline()
        setUpDragGesture()

        NotificationCenter.default.addObserver(
            self, selector: #selector(recomputeActiveRect),
            name: TabletSettings.didChangeNotification, object: nil
        )

        startListening()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        recomputeActiveRect()
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    private func setUpStatusLabel() {
        statusLabel.textColor = .darkGray
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.text = "Waiting for Mac..."
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func setUpSettingsButton() {
        settingsButton.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        settingsButton.tintColor = .darkGray
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        settingsButton.addTarget(self, action: #selector(presentSettings), for: .touchUpInside)
        view.addSubview(settingsButton)
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            settingsButton.widthAnchor.constraint(equalToConstant: 44),
            settingsButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setUpLockButton() {
        lockButton.tintColor = .darkGray
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.addTarget(self, action: #selector(toggleLock), for: .touchUpInside)
        view.addSubview(lockButton)
        NSLayoutConstraint.activate([
            lockButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            lockButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -4),
            lockButton.widthAnchor.constraint(equalToConstant: 44),
            lockButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        updateLockButtonImage()
    }

    @objc private func toggleLock() {
        TabletSettings.positionLocked.toggle()
        updateLockButtonImage()
    }

    private func updateLockButtonImage() {
        let locked = TabletSettings.positionLocked
        let symbol = locked ? "lock.fill" : "lock.open.fill"
        lockButton.setImage(UIImage(systemName: symbol), for: .normal)
        activeAreaOutline.strokeColor = (locked ? UIColor.systemYellow : UIColor.darkGray).cgColor
    }

    private func setUpActiveAreaOutline() {
        activeAreaOutline.strokeColor = UIColor.darkGray.cgColor
        activeAreaOutline.fillColor = UIColor.clear.cgColor
        activeAreaOutline.lineDashPattern = [6, 4]
        activeAreaOutline.lineWidth = 1
        view.layer.addSublayer(activeAreaOutline)
    }

    private func setUpDragGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(pan)
    }

    @objc private func handleDrag(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: view)
            isDraggingActiveArea = !TabletSettings.positionLocked && activeRect.contains(point)
            dragStartRect = activeRect
        case .changed:
            guard isDraggingActiveArea else { return }
            let bounds = view.bounds
            let translation = gesture.translation(in: view)
            var rect = dragStartRect.offsetBy(dx: translation.x, dy: translation.y)
            rect.origin.x = min(max(rect.origin.x, 0), max(bounds.width - rect.width, 0))
            rect.origin.y = min(max(rect.origin.y, 0), max(bounds.height - rect.height, 0))
            activeRect = rect
            activeAreaOutline.path = UIBezierPath(rect: rect).cgPath
        case .ended, .cancelled:
            guard isDraggingActiveArea else { return }
            let bounds = view.bounds
            TabletSettings.offsetX = Double(activeRect.midX - bounds.midX)
            TabletSettings.offsetY = Double(activeRect.midY - bounds.midY)
            isDraggingActiveArea = false
        default:
            break
        }
    }

    @objc private func presentSettings() {
        let hosting = UIHostingController(rootView: SettingsView())
        present(hosting, animated: true)
    }

    @objc private func recomputeActiveRect() {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        TabletSettings.seedDefaultsIfNeeded(width: Double(bounds.width), height: Double(bounds.height))

        let width = min(CGFloat(TabletSettings.activeWidth), bounds.width)
        let height = min(CGFloat(TabletSettings.activeHeight), bounds.height)
        var rect = CGRect(
            x: bounds.midX - width / 2 + CGFloat(TabletSettings.offsetX),
            y: bounds.midY - height / 2 + CGFloat(TabletSettings.offsetY),
            width: width,
            height: height
        )
        rect.origin.x = min(max(rect.origin.x, 0), max(bounds.width - width, 0))
        rect.origin.y = min(max(rect.origin.y, 0), max(bounds.height - height, 0))

        activeRect = rect
        activeAreaOutline.path = UIBezierPath(rect: rect).cgPath
        smoothingAlpha = Float(1.0 - TabletSettings.smoothing)
        updateLockButtonImage()
    }

    private func startListening() {
        let params = NWParameters.tcp
        if let tcpOptions = params.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
        }
        guard let listener = try? NWListener(using: params, on: port) else {
            setStatus("Failed to open listener")
            return
        }
        listener.newConnectionHandler = { [weak self] newConnection in
            self?.accept(newConnection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.setStatus("Listener failed: \(error)")
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    private func accept(_ newConnection: NWConnection) {
        connection?.cancel()
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.setStatus("Connected")
            case .failed(let error):
                self?.setStatus("Connection lost: \(error)")
            case .cancelled:
                self?.setStatus("Waiting for Mac...")
            default:
                break
            }
        }
        newConnection.start(queue: .global(qos: .userInteractive))
        connection = newConnection
    }

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.statusLabel.text = text }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        smoothedX = nil
        smoothedY = nil
        sendPencilTouches(touches, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        sendPencilTouches(touches, event: event)
    }

    private func sendPencilTouches(_ touches: Set<UITouch>, event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
        guard activeRect.width > 0, activeRect.height > 0 else { return }

        for intermediate in coalesced {
            let location = intermediate.location(in: view)
            let normX = min(max(Float((location.x - activeRect.minX) / activeRect.width), 0), 1)
            let normY = min(max(Float((location.y - activeRect.minY) / activeRect.height), 0), 1)

            let filteredX: Float
            let filteredY: Float
            if let prevX = smoothedX, let prevY = smoothedY {
                filteredX = smoothingAlpha * normX + (1 - smoothingAlpha) * prevX
                filteredY = smoothingAlpha * normY + (1 - smoothingAlpha) * prevY
            } else {
                filteredX = normX
                filteredY = normY
            }
            smoothedX = filteredX
            smoothedY = filteredY

            send(normX: filteredX, normY: filteredY)
        }
    }

    private func send(normX: Float, normY: Float) {
        var x = normX
        var y = normY
        let data = Data(bytes: &x, count: MemoryLayout<Float>.size) +
                   Data(bytes: &y, count: MemoryLayout<Float>.size)
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }
}
