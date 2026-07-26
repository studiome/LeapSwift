import Foundation
import LeapC

/// The primary interface to the Ultraleap hand tracking service.
///
/// Create a `LeapController` and consume its `events` stream to receive
/// tracking frames and connection status changes.
///
/// ```swift
/// let controller = try await LeapController()
/// for await event in controller.events {
///     if case .trackingFrame(let frame) = event {
///         print(frame.leftHand?.palm.position ?? "no left hand")
///     }
/// }
/// ```
public actor LeapController {

    // MARK: - Private C State

    // nonisolated(unsafe) lets the polling Task share these C pointers
    // without actor-hop overhead. Access is safe because:
    //   • _connection is set once in init and read-only thereafter
    //   • _device is written only from the actor context (handleDeviceConnected)
    nonisolated(unsafe) private var _connection: LEAP_CONNECTION?
    nonisolated(unsafe) private var _device: LEAP_DEVICE?

    private var pollingTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<LeapEvent>.Continuation?

    // MARK: - Public API

    /// An async stream of all events from the Ultraleap service.
    ///
    /// Terminates when `stop()` is called or the controller is deallocated.
    public nonisolated let events: AsyncStream<LeapEvent>

    /// A convenience stream of only tracking frames (hands data).
    public nonisolated var frames: AsyncMapSequence<AsyncStream<LeapEvent>, HandFrame?> {
        events.map { event -> HandFrame? in
            if case .trackingFrame(let frame) = event { return frame }
            return nil
        }
    }

    // MARK: - Initialisation

    /// Creates a controller and opens a connection to the Ultraleap service.
    /// - Parameter trackingMode: The initial tracking mode. Defaults to `.desktop`.
    public init(trackingMode: TrackingMode = .desktop) async throws {
        // Wire up the AsyncStream before any await so consumers can subscribe immediately.
        var cont: AsyncStream<LeapEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont

        // Set up custom allocator so LeapC can allocate image/mapping buffers.
        // These are non-capturing C function pointers (legal in Swift).
        let allocateFn: @convention(c) (UInt32, eLeapAllocatorType, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { size, _, _ in
            let mem = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
            return mem
        }
        let deallocateFn: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { ptr, _ in
            ptr?.deallocate()
        }

        // Create connection.
        var config = LEAP_CONNECTION_CONFIG()
        config.size = UInt32(MemoryLayout<LEAP_CONNECTION_CONFIG>.size)
        config.flags = 0
        config.tracking_origin = eLeapTrackingOrigin_DeviceCenter

        var conn: LEAP_CONNECTION?
        let createResult = LeapCreateConnection(&config, &conn)
        guard createResult == eLeapRS_Success, let connection = conn else {
            cont.finish()
            throw LeapError(createResult)
        }
        self._connection = connection

        var allocator = LEAP_ALLOCATOR()
        allocator.allocate = allocateFn
        allocator.deallocate = deallocateFn
        LeapSetAllocator(connection, &allocator)

        let openResult = LeapOpenConnection(connection)
        guard openResult == eLeapRS_Success else {
            LeapDestroyConnection(connection)
            self._connection = nil
            cont.finish()
            throw LeapError(openResult)
        }

        // Start the polling loop on a high-priority background task.
        startPolling(connection: connection, mode: trackingMode)
    }

    deinit {
        pollingTask?.cancel()
        eventContinuation?.finish()
        if let device = _device {
            LeapCloseDevice(device)
        }
        if let conn = _connection {
            LeapCloseConnection(conn)
            LeapDestroyConnection(conn)
        }
    }

    // MARK: - Control

    /// Stops event delivery and closes the connection.
    public func stop() {
        pollingTask?.cancel()
        eventContinuation?.finish()
        if let device = _device {
            LeapCloseDevice(device)
            _device = nil
        }
        if let conn = _connection {
            LeapCloseConnection(conn)
            LeapDestroyConnection(conn)
            _connection = nil
        }
    }

    /// Changes the tracking mode asynchronously. The result is delivered via
    /// future events (LeapC applies it asynchronously).
    public func setTrackingMode(_ mode: TrackingMode) throws {
        guard let conn = _connection else {
            throw LeapError.connectionFailed(Int32(eLeapRS_NotConnected.rawValue))
        }
        let result = LeapSetTrackingMode(conn, mode.cValue)
        guard result == eLeapRS_Success else {
            throw LeapError(result)
        }
    }

    /// Enables or disables the background frames policy.
    public func setBackgroundFrames(enabled: Bool) throws {
        guard let conn = _connection else {
            throw LeapError.connectionFailed(Int32(eLeapRS_NotConnected.rawValue))
        }
        let flag = UInt64(eLeapPolicyFlag_BackgroundFrames.rawValue)
        let result = LeapSetPolicyFlags(conn, enabled ? flag : 0, enabled ? 0 : flag)
        guard result == eLeapRS_Success else {
            throw LeapError(result)
        }
    }

    /// Returns the current server and client version information.
    public func version(of part: VersionPart) throws -> (major: Int32, minor: Int32, patch: Int32) {
        guard let conn = _connection else {
            throw LeapError.connectionFailed(Int32(eLeapRS_NotConnected.rawValue))
        }
        var v = LEAP_VERSION()
        let result = LeapGetVersion(conn, part.cValue, &v)
        guard result == eLeapRS_Success else {
            throw LeapError(result)
        }
        return (v.major, v.minor, v.patch)
    }

    // MARK: - Private

    private func startPolling(connection: LEAP_CONNECTION, mode: TrackingMode) {
        pollingTask = Task.detached(priority: .userInitiated) { [weak self] in
            var msg = LEAP_CONNECTION_MESSAGE()
            msg.size = UInt32(MemoryLayout<LEAP_CONNECTION_MESSAGE>.size)

            var trackingModeSet = false

            while !Task.isCancelled {
                let result = LeapPollConnection(connection, 100, &msg)

                guard !Task.isCancelled else { break }

                switch result {
                case eLeapRS_Success:
                    // All pointer data inside `msg` is valid only until the next
                    // LeapPollConnection call. We copy it to Swift value types immediately.
                    let event = Self.convertMessage(msg)
                    if let event {
                        await self?.deliver(event)
                        // Set tracking mode after first connection event
                        if case .connected = event, !trackingModeSet {
                            trackingModeSet = true
                            try? await self?.setTrackingMode(mode)
                        }
                    }
                case eLeapRS_Timeout:
                    continue  // No event; poll again
                case eLeapRS_NotConnected:
                    await self?.deliver(.disconnected)
                    break
                default:
                    break
                }
            }
        }
    }

    // Converts a raw C message to a Swift LeapEvent.
    // IMPORTANT: Must be called synchronously within the polling loop,
    // before the next LeapPollConnection call, to safely dereference pointers.
    private static func convertMessage(_ msg: LEAP_CONNECTION_MESSAGE) -> LeapEvent? {
        switch msg.type {
        case eLeapEventType_Connection:
            return .connected

        case eLeapEventType_ConnectionLost:
            return .disconnected

        case eLeapEventType_Device:
            return .deviceFound(nil)   // device info fetched separately on the actor

        case eLeapEventType_DeviceLost:
            return .deviceLost

        case eLeapEventType_Tracking:
            guard let ptr = msg.tracking_event else { return nil }
            // Copy all hand data out of the C pointer now.
            return .trackingFrame(HandFrame(ptr.pointee))

        default:
            return nil
        }
    }

    private func deliver(_ event: LeapEvent) {
        eventContinuation?.yield(event)

        // When a device connects, open it to enable tracking.
        if case .connected = event {
            openFirstDevice()
        }
    }

    private func openFirstDevice() {
        guard let conn = _connection, _device == nil else { return }

        var count: UInt32 = 0
        LeapGetDeviceList(conn, nil, &count)
        guard count > 0 else { return }

        var refs = [LEAP_DEVICE_REF](repeating: LEAP_DEVICE_REF(), count: Int(count))
        LeapGetDeviceList(conn, &refs, &count)

        var dev: LEAP_DEVICE?
        guard LeapOpenDevice(refs[0], &dev) == eLeapRS_Success, let device = dev else { return }
        self._device = device
    }

    // MARK: - Device Info

    /// Fetches information about the connected device, or `nil` if no device is open.
    public func deviceInfo() -> DeviceInfo? {
        guard let device = _device else { return nil }

        var info = LEAP_DEVICE_INFO()
        info.size = UInt32(MemoryLayout<LEAP_DEVICE_INFO>.size)
        info.serial = nil

        // First call: get required serial buffer length.
        guard LeapGetDeviceInfo(device, &info) == eLeapRS_Success else { return nil }

        let serialLen = Int(info.serial_length)
        return withUnsafeTemporaryAllocation(of: CChar.self, capacity: serialLen) { buf in
            info.serial = buf.baseAddress
            guard LeapGetDeviceInfo(device, &info) == eLeapRS_Success else { return nil }
            return DeviceInfo(info)
        }
    }
}

// MARK: - VersionPart

public enum VersionPart: Sendable {
    case clientLibrary
    case clientProtocol
    case serverLibrary
    case serverProtocol

    var cValue: eLeapVersionPart {
        switch self {
        case .clientLibrary:   return eLeapVersionPart_ClientLibrary
        case .clientProtocol:  return eLeapVersionPart_ClientProtocol
        case .serverLibrary:   return eLeapVersionPart_ServerLibrary
        case .serverProtocol:  return eLeapVersionPart_ServerProtocol
        }
    }
}
