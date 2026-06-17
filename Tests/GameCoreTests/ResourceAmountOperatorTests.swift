import XCTest
@testable import GameCore

/// ResourceAmount compound-operator tests (audit REL-01).
///
/// The `+=` and `-=` operators were added in the style-cleanup pass to satisfy
/// the shorthand_operator advisory. They are now public API, so they need
/// direct tests — not just indirect coverage via Economy. These tests pin:
///   1. component-wise addition,
///   2. component-wise subtraction,
///   3. the load-bearing invariant that subtraction does NOT clamp to zero
///      (clamping is the job of `clampedToNonNegative`).
final class ResourceAmountOperatorTests: XCTestCase {

    // MARK: - +=

    func testCompoundAdditionSumsComponentWise() {
        // Arrange
        var amount = ResourceAmount(food: 1, wood: 2, gold: 3)
        let addend = ResourceAmount(food: 10, wood: 20, gold: 30)
        // Act
        amount += addend
        // Assert — each component sums independently
        XCTAssertEqual(amount.food, 11)
        XCTAssertEqual(amount.wood, 22)
        XCTAssertEqual(amount.gold, 33)
    }

    func testCompoundAdditionIsEquivalentToPlus() {
        // Arrange
        var compound = ResourceAmount(food: 5, wood: 5, gold: 5)
        let direct = ResourceAmount(food: 5, wood: 5, gold: 5)
        let addend = ResourceAmount(food: 2, wood: 3, gold: 4)
        // Act
        compound += addend
        let viaPlus = direct + addend
        // Assert — += must agree with +
        XCTAssertEqual(compound, viaPlus)
    }

    // MARK: - -=

    func testCompoundSubtractionSubtractsComponentWise() {
        // Arrange
        var amount = ResourceAmount(food: 10, wood: 20, gold: 30)
        let subtrahend = ResourceAmount(food: 1, wood: 2, gold: 3)
        // Act
        amount -= subtrahend
        // Assert
        XCTAssertEqual(amount.food, 9)
        XCTAssertEqual(amount.wood, 18)
        XCTAssertEqual(amount.gold, 27)
    }

    /// Subtraction does NOT clamp to zero. This is the load-bearing invariant:
    /// `ResourceAmount` allows negative components during intermediate payment
    /// math (see Economy.greedySolve `remaining.* -= production.*`); clamping
    /// is the explicit job of `clampedToNonNegative()`. If `-=` ever started
    /// clamping, Economy's cost-coverage check would silently break.
    func testCompoundSubtractionDoesNotClampToZero() {
        // Arrange
        var amount = ResourceAmount(food: 1, wood: 1, gold: 1)
        let subtrahend = ResourceAmount(food: 5, wood: 5, gold: 5)
        // Act
        amount -= subtrahend
        // Assert — all components go negative, no clamping
        XCTAssertEqual(amount.food, -4, "subtraction must not clamp food at 0")
        XCTAssertEqual(amount.wood, -4, "subtraction must not clamp wood at 0")
        XCTAssertEqual(amount.gold, -4, "subtraction must not clamp gold at 0")

        // And the explicit clamp is a separate, opt-in step.
        let clamped = amount.clampedToNonNegative()
        XCTAssertEqual(clamped, ResourceAmount(food: 0, wood: 0, gold: 0))
    }
}
