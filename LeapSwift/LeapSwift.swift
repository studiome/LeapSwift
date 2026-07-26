//
//  LeapSwift.swift
//  LeapSwift
//
//  Created by kmiyahara on 2026/07/26.
//

/// LeapSwift: A Swift framework for Ultraleap hand tracking.
///
/// Import `LeapSwift` to start tracking hands with a clean async/await API:
///
/// ```swift
/// import LeapSwift
///
/// let controller = try await LeapController()
/// for await event in controller.events {
///     switch event {
///     case .connected:
///         print("Connected to Ultraleap service")
///     case .trackingFrame(let frame):
///         if let left = frame.leftHand {
///             print("Left palm: \(left.palm.position)")
///         }
///     default:
///         break
///     }
/// }
/// ```
///
/// ## Coordinate System
/// All positions are in **millimeters** relative to the Ultraleap device center.
/// - X: positive toward the user's right
/// - Y: positive upward
/// - Z: positive toward the user (toward the user when device faces up)
/// The version of the LeapSwift framework.
public let frameworkVersion = "1.0.0"

