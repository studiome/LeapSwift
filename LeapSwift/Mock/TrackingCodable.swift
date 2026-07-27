//
//  TrackingCodable.swift
//  LeapSwift
//

import simd

// MARK: - Quaternion Codable

// `simd_quatf` has no `Codable` conformance of its own, so `Bone` — and
// everything nested inside it — can't be encoded without one. Encoded as the
// four raw components `[ix, iy, iz, r]`, matching `simd_quatf`'s own
// memberwise initializer order.
extension simd_quatf: @retroactive Encodable, @retroactive Decodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(imag.x)
        try container.encode(imag.y)
        try container.encode(imag.z)
        try container.encode(real)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let ix = try container.decode(Float.self)
        let iy = try container.decode(Float.self)
        let iz = try container.decode(Float.self)
        let r = try container.decode(Float.self)
        self.init(ix: ix, iy: iy, iz: iz, r: r)
    }
}

// MARK: - Tracking Types Codable

// `Bone`, `Finger`, `Palm`, `Hand`, and `HandFrame` all declare `Codable`
// conformance directly in Types.swift — the compiler only synthesizes
// `init(from:)`/`encode(to:)` when the conformance is declared in the same
// file as the type, so it can't live here alongside the rest of the mocking
// code. With the `Quaternion` conformance above in place, every stored
// property on those types is `Codable` (`Vector3`, i.e. `SIMD3<Float>`, is
// out of the box), so those are plain synthesized conformances — no custom
// `init(from:)`/`encode(to:)` needed. This is what lets ``MockRecording``
// serialize a whole ``HandFrame`` to JSON.
