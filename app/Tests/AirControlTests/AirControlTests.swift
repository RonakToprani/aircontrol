import XCTest
import CoreGraphics
@testable import AirControl

final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> Config {
        try JSONDecoder().decode(Config.self, from: Data(json.utf8))
    }

    func testMissingKeysKeepDefaultsAndPresentKeysAreHonoured() throws {
        let d = Config()
        let c = try decode(#"{"posAlpha": 0.9, "pinchThresh": 0.3, "mouseMode": true}"#)
        XCTAssertEqual(c.posAlpha, 0.9)
        XCTAssertEqual(c.pinchThresh, 0.3)
        XCTAssertTrue(c.mouseMode)
        XCTAssertEqual(c.pinchHyst, d.pinchHyst)
        XCTAssertEqual(c.swipeCooldownMS, d.swipeCooldownMS)
        XCTAssertEqual(c.pinchReleaseGraceMS, d.pinchReleaseGraceMS)
        XCTAssertNil(c.calibration)
    }

    func testEmptyObjectEqualsDefaults() throws {
        XCTAssertEqual(try decode("{}"), Config())
    }

    func testWrongTypedFieldFallsBackWithoutWipingOthers() throws {
        let c = try decode(#"{"posAlpha": "oops", "pinchThresh": 0.3}"#)
        XCTAssertEqual(c.posAlpha, Config().posAlpha)
        XCTAssertEqual(c.pinchThresh, 0.3)
    }

    func testUnknownExtraKeyStillDecodes() throws {
        let c = try decode(#"{"someFutureKnob": 42, "margin": 0.2}"#)
        XCTAssertEqual(c.margin, 0.2)
    }

    func testRoundTripIsEqual() throws {
        var c = Config()
        c.posAlpha = 0.77
        c.swipeMinFingers = 4
        c.mouseMode = true
        c.calibration = CalRect(minX: 0.1, minY: 0.2, maxX: 0.8, maxY: 0.9)
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(Config.self, from: data), c)
    }

    func testTourSandboxIsNeverRestoredFromDisk() throws {
        XCTAssertFalse(Config().tourSandbox)
        XCTAssertFalse(try decode(#"{"tourSandbox": true}"#).tourSandbox)
        var c = Config()
        c.tourSandbox = true
        let data = try JSONEncoder().encode(c)
        XCTAssertFalse(try JSONDecoder().decode(Config.self, from: data).tourSandbox)
    }
}

final class VersionCompareTests: XCTestCase {
    func testIsNewer() {
        XCTAssertTrue(UpdateChecker.isNewer("0.4.1", than: "0.3.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.3.0", than: "0.4.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4.1", than: "0.4.1"))
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4", than: "0.4.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.4.0", than: "0.4"))
        XCTAssertTrue(UpdateChecker.isNewer("0.4.1", than: "0.4"))
        XCTAssertTrue(UpdateChecker.isNewer("1", than: "0.99.99"))
    }
}

final class OneEuroFilterTests: XCTestCase {
    func testConstantInputConverges() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
        var out = 0.0
        for i in 0..<300 { out = f.filter(0.5, at: Double(i) / 60) }
        XCTAssertEqual(out, 0.5, accuracy: 1e-9)
    }

    func testFirstSampleIsPassedThrough() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
        XCTAssertEqual(f.filter(0.8, at: 0), 0.8)
    }

    func testOutputStaysWithinInputRange() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
        for i in 0..<300 {
            let x = i % 2 == 0 ? 0.2 : 0.7
            let y = f.filter(x, at: Double(i) / 60)
            XCTAssertGreaterThanOrEqual(y, 0.2 - 1e-12)
            XCTAssertLessThanOrEqual(y, 0.7 + 1e-12)
        }
    }

    func testStepMovesMonotonicallyTowardNewValue() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
        for i in 0..<60 { _ = f.filter(0.0, at: Double(i) / 60) }
        var prev = 0.0
        for i in 60..<180 {
            let y = f.filter(1.0, at: Double(i) / 60)
            XCTAssertGreaterThanOrEqual(y, prev)
            XCTAssertLessThanOrEqual(y, 1.0 + 1e-12)
            prev = y
        }
        XCTAssertGreaterThan(prev, 0.9)
    }

    func testResetForgetsHistory() {
        let f = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
        _ = f.filter(0.0, at: 0)
        _ = f.filter(0.0, at: 0.016)
        f.reset()
        XCTAssertEqual(f.filter(1.0, at: 1.0), 1.0)
    }
}

final class GestureEngineTests: XCTestCase {
    /// Hand with wrist-to-middleMCP = 0.2, thumb/index tips `gap` hand-sizes apart.
    private func frame(gap: Double, indexMCP: CGPoint = CGPoint(x: 0.5, y: 0.5),
                       t: Double) -> LandmarkFrame {
        let tipX = 0.4 + gap * 0.2
        return LandmarkFrame(
            indexTip: CGPoint(x: tipX, y: 0.5),
            indexMCP: indexMCP,
            thumbTip: CGPoint(x: 0.4, y: 0.5),
            wrist: CGPoint(x: 0.5, y: 0.3),
            joints: [.middleMCP: CGPoint(x: 0.5, y: 0.5)],
            fps: 30, timestamp: t)
    }

    /// Feeds `n` identical frames at 60fps starting at `t`; returns the last state.
    private func feed(_ e: GestureEngine, gap: Double, n: Int, t: inout Double,
                      config: Config) -> GestureState {
        var s = GestureState()
        for _ in 0..<n {
            s = e.process(frame(gap: gap, t: t), config: config, now: t)
            t += 1.0 / 60
        }
        return s
    }

    func testPinchHysteresisHoldsUntilPastReleaseLine() {
        let cfg = Config() // thresh 0.42, hyst 0.12 -> release above 0.54
        let e = GestureEngine()
        var t = 1.0
        XCTAssertFalse(feed(e, gap: 1.0, n: 10, t: &t, config: cfg).pinching)
        XCTAssertTrue(feed(e, gap: 0.2, n: 10, t: &t, config: cfg).pinching)
        // Between engage and release lines: stays pinched indefinitely.
        XCTAssertTrue(feed(e, gap: 0.48, n: 60, t: &t, config: cfg).pinching)
        // Clearly open for well over the release grace: lets go.
        XCTAssertFalse(feed(e, gap: 1.0, n: 30, t: &t, config: cfg).pinching)
    }

    func testSingleNoisyFrameCannotReleaseHeldPinch() {
        let cfg = Config()
        let e = GestureEngine()
        var t = 1.0
        XCTAssertTrue(feed(e, gap: 0.2, n: 20, t: &t, config: cfg).pinching)
        _ = e.process(frame(gap: 1.5, t: t), config: cfg, now: t)
        t += 1.0 / 60
        XCTAssertTrue(feed(e, gap: 0.2, n: 5, t: &t, config: cfg).pinching)
    }

    func testPointerStaysNormalizedEvenWhenHandLeavesRange() {
        let cfg = Config()
        let e = GestureEngine()
        var t = 1.0
        for p in [CGPoint(x: -0.5, y: 2.0), CGPoint(x: 5, y: -3), CGPoint(x: 0.5, y: 0.5)] {
            let s = e.process(frame(gap: 1.0, indexMCP: p, t: t), config: cfg, now: t)
            t += 1.0 / 60
            XCTAssertTrue(s.handVisible)
            XCTAssertTrue((0...1).contains(s.pointer.x) && (0...1).contains(s.pointer.y))
            XCTAssertTrue((0...1).contains(s.anchor.x) && (0...1).contains(s.anchor.y))
        }
    }

    func testNoFrameMeansHandNotVisible() {
        let s = GestureEngine().process(nil, config: Config(), now: 1.0)
        XCTAssertFalse(s.handVisible)
        XCTAssertFalse(s.pinching)
    }
}
