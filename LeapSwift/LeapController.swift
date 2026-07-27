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

    // MARK: - Private Mock State

    private var _mockServer: MockLeapServer?
    private var mockPumpTask: Task<Void, Never>?
    // The policy and scenario this controller was created with, kept around
    // so a `.whenNoDevice` fallback triggered later — by the timeout in
    // `scheduleMockFallbackTimer`, or by an error event in `deliver(_:)` — can
    // start the mock with the same scenario the caller originally asked for.
    private var mockPolicy: MockPolicy = .disabled
    private var mockScenario: MockScenario = .idleRightHand
    // What `setTrackingMode(_:)` stores while mocked, since there is no real
    // connection to apply it to.
    private var mockTrackingMode: TrackingMode = .desktop
    // Set the moment any *real* tracking frame arrives. Both the fallback
    // timer and `deliver(_:)`'s per-event fallback check this so a device
    // that starts producing frames just slowly doesn't get preempted by the
    // mock.
    private var hasReceivedRealFrame = false

    // MARK: - Public API

    /// An async stream of all events from the Ultraleap service.
    ///
    /// Terminates when ``stop()`` is called or the controller is deallocated.
    ///
    /// The stream is unicast: iterating it from two places splits the events
    /// between them rather than delivering each event to both. Iterate once and
    /// rebroadcast if you need multiple consumers.
    public nonisolated let events: AsyncStream<LeapEvent>

    /// A convenience stream of only tracking frames (hands data).
    ///
    /// Every event still produces an element; non-tracking events yield `nil`.
    ///
    /// ```swift
    /// for await frame in controller.frames {
    ///     guard let frame else { continue }
    ///     render(frame)
    /// }
    /// ```
    public nonisolated var frames: AsyncMapSequence<AsyncStream<LeapEvent>, HandFrame?> {
        events.map { event -> HandFrame? in
            if case .trackingFrame(let frame) = event { return frame }
            return nil
        }
    }

    // MARK: - Initialisation

    /// Creates a controller and opens a connection to the Ultraleap service.
    ///
    /// Polling starts immediately on a background task, and the requested
    /// tracking mode is applied as soon as the service reports a connection.
    ///
    /// - Parameters:
    ///   - trackingMode: The initial tracking mode. Defaults to ``TrackingMode/desktop``.
    ///   - mock: Whether to substitute synthetic hand data for a real device.
    ///     Defaults to ``MockPolicy/resolved(environment:arguments:default:)``,
    ///     which is ``MockPolicy/disabled`` unless `LEAPSWIFT_MOCK` or
    ///     `-LeapSwiftMock` says otherwise — so a plain `LeapController()`
    ///     call behaves exactly as it did before mocking existed, and no
    ///     release build streams fake frames without the caller explicitly
    ///     asking for ``MockPolicy/always``.
    ///   - mockScenario: Which canned scenario the mock streams, when active.
    ///     Ignored if `mock` is ``MockPolicy/disabled``.
    /// - Throws: ``LeapError/connectionFailed(_:)`` if the connection cannot be
    ///   created or opened and `mock` is not ``MockPolicy/whenNoDevice`` —
    ///   typically because the Ultraleap Hand Tracking service is not running.
    public init(
        trackingMode: TrackingMode = .desktop,
        mock: MockPolicy = .resolved(),
        mockScenario: MockScenario = .idleRightHand
    ) async throws {
        // Wire up the AsyncStream before any await so consumers can subscribe immediately.
        var cont: AsyncStream<LeapEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.eventContinuation = cont
        self.mockPolicy = mock
        self.mockScenario = mockScenario
        self.mockTrackingMode = trackingMode

        if MockActivation.shouldStartImmediately(policy: mock) {
            startMock(scenario: mockScenario, forwardConnectionEvents: true)
            return
        }

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
            if MockActivation.shouldFallBackOnConnectionFailure(policy: mock) {
                startMock(scenario: mockScenario, forwardConnectionEvents: true)
                return
            }
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
            if MockActivation.shouldFallBackOnConnectionFailure(policy: mock) {
                startMock(scenario: mockScenario, forwardConnectionEvents: true)
                return
            }
            cont.finish()
            throw LeapError(openResult)
        }

        // Start the polling loop on a high-priority background task.
        startPolling(connection: connection, mode: trackingMode)

        if MockActivation.shouldFallBackOnConnectionFailure(policy: mock) {
            scheduleMockFallbackTimer(scenario: mockScenario)
        }
    }

    deinit {
        pollingTask?.cancel()
        mockPumpTask?.cancel()
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
    ///
    /// Finishes ``events``, which ends any `for await` loop over it, then closes
    /// the device and the service connection. Safe to call more than once.
    /// `deinit` performs the same teardown, so calling this is only necessary to
    /// end tracking before the controller is released. A stopped controller
    /// cannot be reconnected — create a new one instead.
    public func stop() {
        pollingTask?.cancel()
        stopMockIfActive()
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

    /// Changes the tracking mode.
    ///
    /// The service applies the change asynchronously, so subsequent frames
    /// reflect the new mode only after a short delay.
    ///
    /// - Parameter mode: The mode to switch to.
    /// - Throws: ``LeapError/connectionFailed(_:)`` if the connection is closed
    ///   or the service rejects the request.
    ///
    /// While mocked, this only records `mode` — there is no real service to
    /// apply it, and no mode-dependent behavior in the synthetic frames.
    public func setTrackingMode(_ mode: TrackingMode) throws {
        guard _mockServer == nil else {
            mockTrackingMode = mode
            return
        }
        guard let conn = _connection else {
            throw LeapError.connectionFailed(Int32(eLeapRS_NotConnected.rawValue))
        }
        let result = LeapSetTrackingMode(conn, mode.cValue)
        guard result == eLeapRS_Success else {
            throw LeapError(result)
        }
    }

    /// Enables or disables the background frames policy.
    ///
    /// With background frames enabled the service keeps delivering tracking data
    /// while your app is not frontmost. The user can veto this policy in the
    /// Ultraleap control panel.
    ///
    /// - Parameter enabled: `true` to request background frames, `false` to
    ///   clear the policy.
    /// - Throws: ``LeapError/connectionFailed(_:)`` if the connection is closed
    ///   or the service rejects the request.
    ///
    /// While mocked, this always succeeds — there is no app-focus concept for
    /// synthetic frames, so there is nothing for the setting to change.
    public func setBackgroundFrames(enabled: Bool) throws {
        guard _mockServer == nil else { return }
        guard let conn = _connection else {
            throw LeapError.connectionFailed(Int32(eLeapRS_NotConnected.rawValue))
        }
        let flag = UInt64(eLeapPolicyFlag_BackgroundFrames.rawValue)
        let result = LeapSetPolicyFlags(conn, enabled ? flag : 0, enabled ? 0 : flag)
        guard result == eLeapRS_Success else {
            throw LeapError.policyError(Int32(result.rawValue))
        }
    }

    /// Returns version information for one component of the tracking stack.
    ///
    /// - Parameter part: Which component to query.
    /// - Returns: The component's major, minor, and patch version numbers.
    /// - Throws: ``LeapError/connectionFailed(_:)`` if the connection is closed
    ///   or the query fails.
    ///
    /// While mocked, this returns a fixed, obviously-synthetic version rather
    /// than throwing, since callers of `version(of:)` typically use it for
    /// display or logging rather than branching on the result.
    public func version(of part: VersionPart) throws -> (major: Int32, minor: Int32, patch: Int32) {
        guard _mockServer == nil else {
            return (major: 0, minor: 0, patch: 0)
        }
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

    // Whether an event should trigger an attempt to open a device.
    //
    // Both cases are needed. The service reports zero devices immediately after
    // `connected` and only enumerates them by the time it emits its device event,
    // so opening on `connected` alone always misses the device; opening on
    // `deviceFound` alone would miss a device already present before we connected.
    static func shouldOpenDevice(for event: LeapEvent) -> Bool {
        switch event {
        case .connected, .deviceFound: return true
        case .disconnected, .deviceLost, .trackingFrame, .error: return false
        }
    }

    // Whether an event means the current device handle is no longer valid.
    static func shouldCloseDevice(for event: LeapEvent) -> Bool {
        if case .deviceLost = event { return true }
        return false
    }

    // Whether the event promises that a device is actually enumerable.
    //
    // `deviceFound` does, so finding none is a real failure worth reporting.
    // After `connected` the service usually has not enumerated one yet, and the
    // `deviceFound` that follows retries — reporting there would be noise.
    static func expectsDeviceToBePresent(for event: LeapEvent) -> Bool {
        if case .deviceFound = event { return true }
        return false
    }

    private func deliver(_ event: LeapEvent) {
        eventContinuation?.yield(event)

        if case .trackingFrame = event {
            hasReceivedRealFrame = true
        }
        if MockActivation.shouldStopMock(event: event) {
            // A real frame arrived while the mock was filling in — hand
            // control back to the device it was standing in for.
            stopMockIfActive()
        }
        if MockActivation.shouldFallBackToMock(policy: mockPolicy, event: event) {
            // `.connected` always precedes any event this can fire for (it's
            // what makes `openFirstDevice` run in the first place), so the
            // mock's own `.connected`/`.deviceFound` would be a confusing
            // duplicate here — only its frames are relayed.
            startMock(scenario: mockScenario, forwardConnectionEvents: false)
        }

        if Self.shouldCloseDevice(for: event) {
            closeDevice()
        }
        if Self.shouldOpenDevice(for: event) {
            openFirstDevice(reportIfMissing: Self.expectsDeviceToBePresent(for: event))
        }
    }

    // MARK: - Mock Wiring

    // Starts `MockLeapServer` and relays its events onto this controller's
    // own `events` stream via a pump task, so consumers see no difference
    // between mocked and real delivery.
    //
    // `forwardConnectionEvents` distinguishes two situations that call this:
    // a cold start (`.always`, or `.whenNoDevice` when even creating/opening
    // the real connection failed) has announced nothing yet, so the mock's
    // own `.connected`/`.deviceFound` are the only announcement there will
    // be. A warm fallback (`.whenNoDevice` after a real `.connected` already
    // fired) only wants the mock's frames — its connection lifecycle events
    // would be duplicates.
    private func startMock(scenario: MockScenario, forwardConnectionEvents: Bool) {
        guard _mockServer == nil else { return }
        let server = MockLeapServer(scenario: scenario)
        _mockServer = server
        mockPumpTask = Task { [weak self] in
            for await event in server.events {
                if !forwardConnectionEvents, Self.isConnectionLifecycleEvent(event) {
                    continue
                }
                guard let self else { break }
                await self.relayMockEvent(event)
            }
        }
        Task { await server.start() }
    }

    // Stops the mock server, if one is running, and lets its own pump task
    // wind down once `server.stop()` finishes its stream. Safe to call when
    // no mock is active.
    private func stopMockIfActive() {
        guard let server = _mockServer else { return }
        _mockServer = nil
        let pump = mockPumpTask
        mockPumpTask = nil
        Task {
            await server.stop()
            pump?.cancel()
        }
    }

    private func relayMockEvent(_ event: LeapEvent) {
        eventContinuation?.yield(event)
    }

    private static func isConnectionLifecycleEvent(_ event: LeapEvent) -> Bool {
        switch event {
        case .connected, .deviceFound: return true
        case .disconnected, .deviceLost, .trackingFrame, .error: return false
        }
    }

    // `.whenNoDevice` only: if no real tracking frame has arrived within
    // `timeout` of a successful connection, falls back to the mock even
    // though no explicit error ever came through — covers a device that is
    // simply slow to start producing frames, or a `deviceFound` that never
    // arrives at all.
    private func scheduleMockFallbackTimer(scenario: MockScenario, timeout: Duration = .seconds(2)) {
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.fallBackToMockIfStillNoRealFrame(scenario: scenario)
        }
    }

    private func fallBackToMockIfStillNoRealFrame(scenario: MockScenario) {
        guard !hasReceivedRealFrame, _mockServer == nil else { return }
        startMock(scenario: scenario, forwardConnectionEvents: false)
    }

    // Releases the device handle so a later `deviceFound` can open a fresh one.
    private func closeDevice() {
        guard let device = _device else { return }
        LeapCloseDevice(device)
        _device = nil
    }

    private func openFirstDevice(reportIfMissing: Bool) {
        guard let conn = _connection, _device == nil else { return }

        var count: UInt32 = 0
        LeapGetDeviceList(conn, nil, &count)
        guard count > 0 else {
            if reportIfMissing { report(.deviceNotFound) }
            return
        }

        var refs = [LEAP_DEVICE_REF](repeating: LEAP_DEVICE_REF(), count: Int(count))
        LeapGetDeviceList(conn, &refs, &count)

        var dev: LEAP_DEVICE?
        let result = LeapOpenDevice(refs[0], &dev)
        guard result == eLeapRS_Success, let device = dev else {
            report(.openDeviceFailed(Int32(result.rawValue)))
            return
        }
        self._device = device
    }

    // Yields an error directly rather than through `deliver`, so that reporting a
    // failure cannot itself trigger another open attempt.
    private func report(_ error: LeapError) {
        eventContinuation?.yield(.error(error))
    }

    // MARK: - Device Info

    /// Fetches information about the connected device, or `nil` if no device is open.
    ///
    /// The controller opens the first available device shortly after
    /// ``LeapEvent/connected``, so this returns `nil` until that completes and
    /// again after ``stop()``.
    ///
    /// While mocked, this returns a pseudo device rather than `nil`, since a
    /// mock always has a "device" from the moment it starts.
    public func deviceInfo() async -> DeviceInfo? {
        if let server = _mockServer {
            return await server.deviceInfo()
        }
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

/// Which component's version to query with ``LeapController/version(of:)``.
///
/// Frozen: these are the four components the LeapC version API exposes, so the
/// set will not grow. Callers can switch over it exhaustively without
/// `@unknown default`.
@frozen
public enum VersionPart: Sendable {
    /// The version of the LeapC client library linked into this process.
    case clientLibrary
    /// The protocol version the client library speaks.
    case clientProtocol
    /// The version of the Ultraleap tracking service.
    case serverLibrary
    /// The protocol version the service speaks.
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
