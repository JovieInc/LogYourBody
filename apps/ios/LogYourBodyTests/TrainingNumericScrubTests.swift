import XCTest
@testable import LogYourBody

final class TrainingNumericScrubTests: XCTestCase {
    func testAllDimensionsSnapAtTheirOwnStepAndClampWithoutWrapping() throws {
        let fixtures: [(TrainingNumericDimension, String, Double, String)] = [
            (.reps, "10", 1, "12"), (.rir, "3", 1, "5"),
            (.load(.metric), "22.5", 0.5, "23.5"), (.restSeconds, "90", 5, "100")
        ]
        for (dimension, original, increment, expected) in fixtures {
            var edit = try XCTUnwrap(TrainingNumericScrubEdit(
                original: original, dimension: dimension, increment: increment
            ))
            XCTAssertFalse(edit.move(horizontal: 5, vertical: 0), "Pixels below a snapped step do not tick")
            XCTAssertNil(edit.committedText(current: original))
            XCTAssertTrue(edit.move(horizontal: 24, vertical: 0))
            XCTAssertEqual(edit.committedText(current: original), expected)
            edit.move(horizontal: 1_000_000, vertical: 0)
            XCTAssertEqual(edit.value, dimension.adjusted(dimension.bounds.upperBound, by: 0))
            XCTAssertFalse(edit.move(horizontal: 2_000_000, vertical: 0), "No haptic beyond the bound")
            edit.move(horizontal: -1_000_000, vertical: 0)
            XCTAssertEqual(edit.value, dimension.bounds.lowerBound)
        }
    }

    func testFastAndSlowSamplesReachTheSameValueWithoutFlickOvershoot() throws {
        var fast = try XCTUnwrap(TrainingNumericScrubEdit(original: "10", dimension: .reps, increment: 1))
        var slow = fast
        fast.move(horizontal: 72, vertical: 0)
        for pixel in stride(from: 1, through: 72, by: 1) { slow.move(horizontal: Double(pixel), vertical: 0) }
        XCTAssertEqual(fast.value, 16)
        XCTAssertEqual(slow.value, fast.value)
        XCTAssertFalse(slow.move(horizontal: 72, vertical: 0))
    }

    func testFineModeSlowsSubsequentMotionWithoutJumpingAtTheTransition() throws {
        var edit = try XCTUnwrap(TrainingNumericScrubEdit(original: "10", dimension: .reps, increment: 1))
        edit.move(horizontal: 24, vertical: 0)
        XCTAssertEqual(edit.value, 12)
        XCTAssertFalse(edit.move(horizontal: 24, vertical: -60))
        XCTAssertFalse(edit.move(horizontal: 48, vertical: -60))
        edit.move(horizontal: 72, vertical: -60)
        XCTAssertEqual(edit.value, 13)
    }

    func testCancellationIsStickyAndStaleBindingCannotBeOverwritten() throws {
        var edit = try XCTUnwrap(TrainingNumericScrubEdit(original: "3", dimension: .rir, increment: 1))
        edit.move(horizontal: 24, vertical: 0)
        XCTAssertNil(edit.committedText(current: "4"))
        edit.move(horizontal: 36, vertical: 90)
        XCTAssertTrue(edit.cancelled)
        edit.move(horizontal: 48, vertical: 0)
        XCTAssertNil(edit.committedText(current: "3"))
    }

    func testReturnToOriginAndSubthresholdDragPreserveExactCanonicalPounds() throws {
        let original = "60.123456789"
        var edit = try XCTUnwrap(TrainingNumericScrubEdit(
            original: original, dimension: .load(.imperial), increment: 1
        ))
        edit.move(horizontal: 3, vertical: 0)
        XCTAssertNil(edit.committedText(current: original))
        edit.move(horizontal: 36, vertical: 0)
        edit.move(horizontal: 0, vertical: 0)
        XCTAssertNil(edit.committedText(current: original))
    }

    func testImperialEntryIsConvertedOnceToCanonicalKilogramsAndNeverDoubled() throws {
        let dimension = TrainingNumericDimension.load(.imperial)
        let canonical = try XCTUnwrap(dimension.canonicalText("50"))
        XCTAssertEqual(try XCTUnwrap(Double(canonical)), UnitConversion.lbsToKg(50), accuracy: 1e-7)
        XCTAssertEqual(dimension.displayText(canonical), "50")
        XCTAssertEqual(TrainingNumericDimension.load(.metric).displayText(canonical), "22.68")
        XCTAssertNotEqual(Double(canonical), 50, "Pounds cannot be injected as kilograms")
        XCTAssertNil(dimension.canonicalText("50 lb"))
        XCTAssertNil(dimension.canonicalText("50 kg"))
    }

    func testUserSelectedEquipmentIncrementDoesNotMultiplyPerHandLoad() throws {
        var edit = try XCTUnwrap(TrainingNumericScrubEdit(
            original: "22.5", dimension: .load(.metric), increment: 1.25
        ))
        edit.move(horizontal: 24, vertical: 0)
        XCTAssertEqual(edit.committedText(current: "22.5"), "25")
        XCTAssertNil(TrainingNumericScrubEdit(original: "22.5", dimension: .load(.metric), increment: -1))
    }

    func testKeyboardDecimalCommaBodyweightAndAllNumericBounds() throws {
        XCTAssertEqual(TrainingNumericDimension.load(.metric).canonicalText("22,75"), "22.75")
        XCTAssertEqual(TrainingNumericDimension.load(.metric).canonicalText(""), "")
        XCTAssertEqual(TrainingNumericDimension.load(.metric).canonicalText("0"), "0")
        XCTAssertNil(TrainingNumericDimension.load(.metric).canonicalText("500.01"))
        XCTAssertNil(TrainingNumericDimension.load(.imperial).canonicalText("1103"))
        for dimension in [TrainingNumericDimension.reps, .rir, .restSeconds] {
            XCTAssertNotNil(dimension.canonicalText(String(Int(dimension.bounds.lowerBound))))
            XCTAssertNotNil(dimension.canonicalText(String(Int(dimension.bounds.upperBound))))
            XCTAssertNil(dimension.canonicalText(String(Int(dimension.bounds.upperBound) + 1)))
            XCTAssertNil(dimension.canonicalText("2.5"))
            XCTAssertNil(dimension.canonicalText(""))
        }
        for invalid in ["-1", "NaN", "inf", "1e3", "1,2.3", "abc"] {
            XCTAssertNil(TrainingNumericDimension.load(.metric).canonicalText(invalid))
            XCTAssertNil(TrainingNumericScrubEdit(original: invalid, dimension: .load(.metric), increment: 0.5))
        }
    }

    func testBlankLoadStartsAtZeroAndInvalidOrFractionalRepsCannotScrub() throws {
        var bodyweight = try XCTUnwrap(TrainingNumericScrubEdit(
            original: "", dimension: .load(.metric), increment: 0.5
        ))
        XCTAssertNil(bodyweight.committedText(current: ""))
        bodyweight.move(horizontal: 12, vertical: 0)
        XCTAssertEqual(bodyweight.committedText(current: ""), "0.5")
        XCTAssertNil(TrainingNumericScrubEdit(original: "0", dimension: .reps, increment: 1))
        XCTAssertNil(TrainingNumericScrubEdit(original: "2.5", dimension: .reps, increment: 1))
    }
}
