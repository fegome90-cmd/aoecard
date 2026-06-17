import Foundation

/// Validation finding (error or warning).
public struct ValidationFinding: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }
    public let severity: Severity
    public let deckId: String
    public let message: String

    public init(_ severity: Severity, deckId: String, _ message: String) {
        self.severity = severity
        self.deckId = deckId
        self.message = message
    }

    public var description: String {
        "[\(severity.rawValue)] \(deckId): \(message)"
    }
}

/// Result of validating one or more decks.
public struct ValidationResult: Sendable {
    public var findings: [ValidationFinding]
    public var isValid: Bool { !findings.contains { $0.severity == .error } }

    public init(findings: [ValidationFinding] = []) { self.findings = findings }

    public var errors: [ValidationFinding] { findings.filter { $0.severity == .error } }
    public var warnings: [ValidationFinding] { findings.filter { $0.severity == .warning } }
}

/// Validates a deck list against the rules and the card database.
public struct DeckValidator: Sendable {
    public let cards: [String: Card]
    public let rules: Rules

    public init(cards: [String: Card], rules: Rules) {
        self.cards = cards
        self.rules = rules
    }

    /// Validate a single deck list.
    public func validate(_ deck: DeckList) -> ValidationResult {
        var findings: [ValidationFinding] = []
        let deckId = deck.id

        // 1. Stronghold & civilization match.
        guard let stronghold = cards[deck.strongholdId] else {
            findings.append(.init(.error, deckId: deckId, "stronghold not found: \(deck.strongholdId)"))
            return ValidationResult(findings: findings)
        }
        if stronghold.type != .stronghold {
            findings.append(.init(.error, deckId: deckId, "stronghold card is not type=stronghold: \(deck.strongholdId)"))
        }
        if stronghold.civilization != deck.civilization {
            findings.append(.init(.error, deckId: deckId,
                "stronghold civilization (\(stronghold.civilization.label)) does not match deck (\(deck.civilization.label))"))
        }

        // 2. Total counts.
        if deck.empire.count != rules.decks.empireTotal {
            findings.append(.init(.error, deckId: deckId,
                "empire deck has \(deck.empire.count) cards, expected \(rules.decks.empireTotal)"))
        }
        if deck.tactics.count != rules.decks.tacticsTotal {
            findings.append(.init(.error, deckId: deckId,
                "tactics deck has \(deck.tactics.count) cards, expected \(rules.decks.tacticsTotal)"))
        }

        // 3. Per-type breakdowns.
        findings.append(contentsOf: checkBreakdown(slot: deck.empire, expected: rules.decks.empireBreakdown,
                                                    section: "empire", deckId: deckId))
        findings.append(contentsOf: checkBreakdown(slot: deck.tactics, expected: rules.decks.tacticsBreakdown,
                                                    section: "tactics", deckId: deckId))

        // 4. Every referenced card must exist and be legal for this civilization.
        let legalCivs: Set<Civilization> = [deck.civilization, .neutral]
        for (id, count) in counts(of: deck.empire + deck.tactics) {
            guard let card = cards[id] else {
                findings.append(.init(.error, deckId: deckId, "card not found: \(id)"))
                continue
            }
            // Civilization legality: a card's civ must be in {deck.civ, neutral}.
            if !legalCivs.contains(card.civilization) {
                findings.append(.init(.error, deckId: deckId,
                    "card \(id) is \(card.civilization.label), not legal for \(deck.civilization.label) deck"))
            }
            // maxCopiesInDeck (only enforced when the card declares it).
            if let cap = card.limits.maxCopiesInDeck, count > cap {
                findings.append(.init(.error, deckId: deckId,
                    "card \(id) appears \(count)×, exceeds maxCopiesInDeck=\(cap)"))
            }
        }

        // 5. Empire cards must be empire-typed; tactics cards must be tactics-typed.
        for id in deck.empire {
            if let c = cards[id], !c.type.isEmpire {
                findings.append(.init(.error, deckId: deckId,
                    "card \(id) is type \(c.type) in empire deck (not an empire type)"))
            }
        }
        for id in deck.tactics {
            if let c = cards[id], !c.type.isTactics {
                findings.append(.init(.error, deckId: deckId,
                    "card \(id) is type \(c.type) in tactics deck (not a tactics type)"))
            }
        }

        // 6. Province + starting resource sanity.
        let expectedProvinces = rules.setup.provincesPerPlayer - 1 // 4 outer; stronghold is separate
        if deck.provinceIds.count != expectedProvinces {
            findings.append(.init(.warning, deckId: deckId,
                "expected \(expectedProvinces) outer provinces, found \(deck.provinceIds.count)"))
        }
        for id in deck.provinceIds {
            guard let p = cards[id] else {
                findings.append(.init(.error, deckId: deckId, "province not found: \(id)"))
                continue
            }
            if p.type != .province {
                findings.append(.init(.error, deckId: deckId, "card \(id) is not type=province"))
            }
        }
        if deck.startingResourceIds.count != rules.setup.startingResourceCount {
            findings.append(.init(.warning, deckId: deckId,
                "expected \(rules.setup.startingResourceCount) starting resources, found \(deck.startingResourceIds.count)"))
        }
        for id in deck.startingResourceIds {
            guard let resource = cards[id] else {
                findings.append(.init(.error, deckId: deckId, "starting resource not found: \(id)"))
                continue
            }
            if resource.type != .resource {
                findings.append(.init(.error, deckId: deckId, "starting card \(id) is not type=resource"))
            }
        }

        return ValidationResult(findings: findings)
    }

    /// Validate every deck list in the catalog.
    public func validateAll(_ decks: [String: DeckList]) -> [(DeckList, ValidationResult)] {
        decks.values.sorted(by: { $0.id < $1.id }).map { ($0, validate($0)) }
    }

    // MARK: - Helpers

    private func counts(of ids: [String]) -> [String: Int] {
        var c: [String: Int] = [:]
        for id in ids { c[id, default: 0] += 1 }
        return c
    }

    private func checkBreakdown(slot: [String], expected: [String: Int],
                                section: String, deckId: String) -> [ValidationFinding] {
        var actual: [String: Int] = [:]
        for id in slot {
            guard let card = cards[id] else { continue }
            actual[card.type.rawValue, default: 0] += 1
        }
        var out: [ValidationFinding] = []
        for (typeName, want) in expected.sorted(by: { $0.key < $1.key }) {
            let got = actual[typeName] ?? 0
            if got != want {
                out.append(.init(.error, deckId: deckId,
                    "\(section) has \(got) \(typeName), expected \(want)"))
            }
        }
        return out
    }
}
