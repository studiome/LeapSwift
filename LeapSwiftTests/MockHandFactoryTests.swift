//
//  MockHandFactoryTests.swift
//  LeapSwiftTests
//

import Testing
import Foundation
import simd
@testable import LeapSwift

private let tolerance: Float = 0.01

// MARK: - Skeleton Invariants

@Suite("MockHandFactory skeleton invariants")
struct MockHandFactorySkeletonTests {

    private func samplePose(curl: Float = 0.4) -> MockHandPose {
        MockHandPose(position: .init(10, 200, 30), orientation: .identity,
                     curl: .init(repeating: curl), thumbCurl: curl)
    }

    @Test func handHasFiveFingers() {
        let hand = MockHandFactory.hand(type: .right, id: 1, pose: samplePose())
        #expect(hand.fingers.count == 5)
    }

    @Test func everyFingerHasFourBones() {
        let hand = MockHandFactory.hand(type: .right, id: 1, pose: samplePose())
        for finger in hand.fingers {
            #expect(finger.bones.count == 4)
        }
    }

    @Test func bonesChainContinuously() {
        let hand = MockHandFactory.hand(type: .right, id: 1, pose: samplePose())
        for finger in hand.fingers {
            let bones = finger.bones
            for i in 0..<(bones.count - 1) {
                #expect(simd_distance(bones[i].nextJoint, bones[i + 1].previousJoint) < tolerance)
            }
        }
    }

    @Test func thumbMetacarpalIsZeroLength() {
        let hand = MockHandFactory.hand(type: .right, id: 1, pose: samplePose())
        #expect(hand.thumb.metacarpal.length < tolerance)
    }

    @Test("Strengths and confidence stay within 0...1", arguments: [0.0, 0.25, 0.5, 0.75, 1.0] as [Float])
    func strengthsStayInUnitRange(curl: Float) {
        let hand = MockHandFactory.hand(type: .right, id: 1, pose: samplePose(curl: curl))
        #expect((0...1).contains(hand.pinchStrength))
        #expect((0...1).contains(hand.grabStrength))
        #expect((0...1).contains(hand.confidence))
        for finger in hand.fingers {
            _ = finger.isExtended // must not trap; boolean is trivially in range
        }
    }

    @Test func sameTimeProducesIdenticalFrame() {
        let a = MockHandFactory.frame(scenario: .wave, frameId: 7, time: 1.234)
        let b = MockHandFactory.frame(scenario: .wave, frameId: 7, time: 1.234)
        #expect(a.hands.count == b.hands.count)
        guard let handA = a.rightHand, let handB = b.rightHand else {
            Issue.record("expected a right hand")
            return
        }
        #expect(handA.palm.position == handB.palm.position)
        #expect(handA.thumb.distal.nextJoint == handB.thumb.distal.nextJoint)
        #expect(handA.pinchStrength == handB.pinchStrength)
    }

    @Test func leftHandMirrorsRightHandAcrossXAxis() {
        let pose = MockHandPose(position: .zero, orientation: .identity,
                                curl: .init(repeating: 0.3), thumbCurl: 0.3)
        let right = MockHandFactory.hand(type: .right, id: 1, pose: pose)
        let left = MockHandFactory.hand(type: .left, id: 2, pose: pose)

        for (rf, lf) in zip(right.fingers, left.fingers) {
            for (rb, lb) in zip(rf.bones, lf.bones) {
                #expect(abs(rb.nextJoint.x + lb.nextJoint.x) < tolerance)
                #expect(abs(rb.nextJoint.y - lb.nextJoint.y) < tolerance)
                #expect(abs(rb.nextJoint.z - lb.nextJoint.z) < tolerance)
            }
        }
    }
}

// MARK: - Scenario Characteristics

@Suite("MockHandFactory scenario characteristics")
struct MockHandFactoryScenarioTests {

    @Test func noHandsScenarioHasNoHands() {
        let frame = MockHandFactory.frame(scenario: .noHands, frameId: 0, time: 0)
        #expect(frame.hands.isEmpty)
    }

    @Test func idleRightHandScenarioHasOnlyARightHand() {
        let frame = MockHandFactory.frame(scenario: .idleRightHand, frameId: 0, time: 0.5)
        #expect(frame.rightHand != nil)
        #expect(frame.leftHand == nil)
    }

    @Test func bothHandsIdleScenarioHasBothHands() {
        let frame = MockHandFactory.frame(scenario: .bothHandsIdle, frameId: 0, time: 0.5)
        #expect(frame.rightHand != nil)
        #expect(frame.leftHand != nil)
    }

    @Test func openCloseScenarioReachesBothOpenAndClosed() {
        var minGrab: Float = .infinity
        var maxGrab: Float = -.infinity
        for i in 0..<60 {
            let t = TimeInterval(i) * 0.05
            guard let hand = MockHandFactory.frame(scenario: .openClose, frameId: Int64(i), time: t).rightHand else {
                continue
            }
            minGrab = min(minGrab, hand.grabStrength)
            maxGrab = max(maxGrab, hand.grabStrength)
        }
        #expect(minGrab < 0.05)
        #expect(maxGrab > 0.95)
    }

    @Test func pinchScenarioReachesFullPinchStrength() {
        var maxPinch: Float = -.infinity
        for i in 0..<60 {
            let t = TimeInterval(i) * 0.05
            guard let hand = MockHandFactory.frame(scenario: .pinch, frameId: Int64(i), time: t).rightHand else {
                continue
            }
            maxPinch = max(maxPinch, hand.pinchStrength)
        }
        #expect(maxPinch >= 0.999)
    }

    @Test func waveScenarioSweepsPalmX() {
        var minX: Float = .infinity
        var maxX: Float = -.infinity
        for i in 0..<60 {
            let t = TimeInterval(i) * 0.05
            guard let hand = MockHandFactory.frame(scenario: .wave, frameId: Int64(i), time: t).rightHand else {
                continue
            }
            minX = min(minX, hand.palm.position.x)
            maxX = max(maxX, hand.palm.position.x)
        }
        #expect(maxX - minX > 50)
    }
}
