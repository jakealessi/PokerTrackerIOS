//
//  PokerEquityEngine.swift
//  PokerTrackerIOS
//
//  Hybrid equity calculator: exact when fast, Monte Carlo when many runouts.
//  Target: never exceed 3–4 seconds.
//

import Foundation

// MARK: - Card

struct PlayingCard: Hashable, Equatable {
    let rank: Rank
    let suit: Suit

    enum Rank: Int, CaseIterable {
        case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace
        var value: Int { rawValue }
    }

    enum Suit: String, CaseIterable {
        case spades = "s", hearts = "h", diamonds = "d", clubs = "c"
    }

    static let fullDeck: [PlayingCard] = {
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { PlayingCard(rank: $0, suit: suit) }
        }
    }()
}

// MARK: - Game Type

enum EquityGameType {
    case nlh  // 2 cards per hand
    case plo  // 4 cards per hand

    var cardsPerHand: Int {
        switch self {
        case .nlh: return 2
        case .plo: return 4
        }
    }
}

// MARK: - Equity Result

struct EquityResult {
    let wins: [Int]      // per hand
    let ties: [Double]   // per hand (fractional: 1/n per tied runout)
    let totalRunouts: Int

    func winPercent(forHand i: Int) -> Double {
        guard totalRunouts > 0 else { return 0 }
        return Double(wins[i]) / Double(totalRunouts) * 100
    }

    func tiePercent(forHand i: Int) -> Double {
        guard totalRunouts > 0 else { return 0 }
        return ties[i] / Double(totalRunouts) * 100
    }
}

// MARK: - Hand Evaluator (5-card)

struct HandEvaluator {
    /// Returns a comparable value; higher = better hand
    static func rank(_ five: [PlayingCard]) -> UInt64 {
        precondition(five.count == 5)
        return rank(five[0], five[1], five[2], five[3], five[4])
    }

    @inline(__always)
    static func rank(_ c0: PlayingCard, _ c1: PlayingCard, _ c2: PlayingCard, _ c3: PlayingCard, _ c4: PlayingCard) -> UInt64 {
        var a = c0.rank.rawValue
        var b = c1.rank.rawValue
        var c = c2.rank.rawValue
        var d = c3.rank.rawValue
        var e = c4.rank.rawValue

        sort5Descending(&a, &b, &c, &d, &e)

        let isFlush = c0.suit == c1.suit && c0.suit == c2.suit && c0.suit == c3.suit && c0.suit == c4.suit
        let straightHigh = straightHighCard(a, b, c, d, e)

        if isFlush, let high = straightHigh {
            return packedRank(category: 8, high, 0, 0, 0, 0)
        }

        // 4 of a kind: AAAAB or BAAAA
        if a == d {
            return packedRank(category: 7, a, e, 0, 0, 0)
        }
        if b == e {
            return packedRank(category: 7, b, a, 0, 0, 0)
        }

        // Full house: AAABB or AABBB
        if a == c, d == e {
            return packedRank(category: 6, a, d, 0, 0, 0)
        }
        if a == b, c == e {
            return packedRank(category: 6, c, a, 0, 0, 0)
        }

        if isFlush {
            return packedRank(category: 5, a, b, c, d, e)
        }
        if let high = straightHigh {
            return packedRank(category: 4, high, 0, 0, 0, 0)
        }

        // Trips: AAABC / ABBBC / ACDDD
        if a == c {
            return packedRank(category: 3, a, d, e, 0, 0)
        }
        if b == d {
            return packedRank(category: 3, b, a, e, 0, 0)
        }
        if c == e {
            return packedRank(category: 3, c, a, b, 0, 0)
        }

        // Two pair: AABBC / AABCC / ABBCC
        if a == b, c == d {
            return packedRank(category: 2, a, c, e, 0, 0)
        }
        if a == b, d == e {
            return packedRank(category: 2, a, d, c, 0, 0)
        }
        if b == c, d == e {
            return packedRank(category: 2, b, d, a, 0, 0)
        }

        // One pair
        if a == b {
            return packedRank(category: 1, a, c, d, e, 0)
        }
        if b == c {
            return packedRank(category: 1, b, a, d, e, 0)
        }
        if c == d {
            return packedRank(category: 1, c, a, b, e, 0)
        }
        if d == e {
            return packedRank(category: 1, d, a, b, c, 0)
        }

        // High card
        return packedRank(category: 0, a, b, c, d, e)
    }

    @inline(__always)
    private static func straightHighCard(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ e: Int) -> Int? {
        // Sorted descending; duplicates cannot be a straight.
        if a == b || b == c || c == d || d == e { return nil }
        if a == 14, b == 5, c == 4, d == 3, e == 2 { return 5 } // wheel
        if a - b == 1, b - c == 1, c - d == 1, d - e == 1 { return a }
        return nil
    }

    @inline(__always)
    private static func packedRank(category: UInt64, _ k1: Int, _ k2: Int, _ k3: Int, _ k4: Int, _ k5: Int) -> UInt64 {
        // [category:4 bits][k1..k5:4 bits], with zero padding for missing kickers.
        return (category << 20)
            | (UInt64(k1) << 16)
            | (UInt64(k2) << 12)
            | (UInt64(k3) << 8)
            | (UInt64(k4) << 4)
            | UInt64(k5)
    }

    @inline(__always)
    private static func sort5Descending(_ a: inout Int, _ b: inout Int, _ c: inout Int, _ d: inout Int, _ e: inout Int) {
        cmpSwapDesc(&a, &b)
        cmpSwapDesc(&d, &e)
        cmpSwapDesc(&c, &e)
        cmpSwapDesc(&c, &d)
        cmpSwapDesc(&b, &e)
        cmpSwapDesc(&a, &d)
        cmpSwapDesc(&a, &c)
        cmpSwapDesc(&b, &d)
        cmpSwapDesc(&b, &c)
    }

    @inline(__always)
    private static func cmpSwapDesc(_ x: inout Int, _ y: inout Int) {
        if x < y {
            swap(&x, &y)
        }
    }
}

// MARK: - Equity Calculator

struct PokerEquityEngine {
    let gameType: EquityGameType
    let hands: [[PlayingCard]]
    let board: [PlayingCard]
    let deadCards: [PlayingCard]

    init(gameType: EquityGameType, hands: [[PlayingCard]], board: [PlayingCard], deadCards: [PlayingCard] = []) {
        self.gameType = gameType
        self.hands = hands
        self.board = board
        self.deadCards = deadCards
    }

    /// Max runouts for exact enumeration; above this we use Monte Carlo.
    private static let exactThreshold = 50_000
    /// Monte Carlo sample count when exact would be too slow.
    private static let monteCarloSamples = 60_000
    private typealias FiveIndexCombo = (Int, Int, Int, Int, Int)
    private typealias TwoIndexCombo = (Int, Int)
    private typealias ThreeIndexCombo = (Int, Int, Int)
    private static let nlhFiveFromSevenCombos = makeFiveIndexCombinations(n: 7)
    private static let ploHandTwoCombos = makeTwoIndexCombinations(n: 4)
    private static let ploBoardThreeCombos = makeThreeIndexCombinations(n: 5)

    func calculate() -> EquityResult? {
        let used = Set(hands.flatMap { $0 } + board + deadCards)
        let deck = PlayingCard.fullDeck.filter { !used.contains($0) }

        let cardsToDeal = 5 - board.count
        guard cardsToDeal >= 0, deck.count >= cardsToDeal else { return nil }

        var wins = Array(repeating: 0, count: hands.count)
        var ties = Array(repeating: 0.0, count: hands.count)
        var tieScratch = Array(repeating: 0, count: hands.count)
        var total = 0

        if cardsToDeal == 0 {
            evaluateAll(board: board, wins: &wins, ties: &ties, tieScratch: &tieScratch)
            total = 1
        } else {
            let totalCombos = countCombinations(n: deck.count, k: cardsToDeal)
            let useMonteCarlo = board.count == 0 || totalCombos > Double(Self.exactThreshold)
            if !useMonteCarlo {
                // Exact enumeration (flop/turn only; preflop always uses Monte Carlo)
                var combo = Array(repeating: 0, count: cardsToDeal)
                var fullBoard = board
                fullBoard.reserveCapacity(5)
                enumerateCombinations(n: deck.count, k: cardsToDeal, start: 0, depth: 0, combo: &combo) { runoutIndices in
                    if fullBoard.count > board.count {
                        fullBoard.removeLast(fullBoard.count - board.count)
                    }
                    for i in 0..<cardsToDeal {
                        fullBoard.append(deck[runoutIndices[i]])
                    }
                    evaluateAll(board: fullBoard, wins: &wins, ties: &ties, tieScratch: &tieScratch)
                    total += 1
                }
            } else {
                // Monte Carlo sampling
                total = runMonteCarlo(deck: deck, cardsToDeal: cardsToDeal, wins: &wins, ties: &ties)
            }
        }

        return EquityResult(wins: wins, ties: ties, totalRunouts: total)
    }

    private func countCombinations(n: Int, k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result: Double = 1
        for i in 0..<k {
            result *= Double(n - i) / Double(i + 1)
        }
        return result
    }

    private func runMonteCarlo(deck: [PlayingCard], cardsToDeal: Int, wins: inout [Int], ties: inout [Double]) -> Int {
        let maxSamples = min(Self.monteCarloSamples, Int(countCombinations(n: deck.count, k: cardsToDeal)))
        let samples = min(maxSamples, adaptiveMonteCarloSamples(cardsToDeal: cardsToDeal))
        var indices = Array(0..<deck.count)
        var tieScratch = Array(repeating: 0, count: hands.count)
        var fullBoard = board
        fullBoard.reserveCapacity(5)

        for _ in 0..<samples {
            // Fisher-Yates partial shuffle: random k cards without replacement
            for i in 0..<cardsToDeal {
                let j = i + Int.random(in: 0..<(deck.count - i))
                indices.swapAt(i, j)
            }
            if fullBoard.count > board.count {
                fullBoard.removeLast(fullBoard.count - board.count)
            }
            for i in 0..<cardsToDeal {
                fullBoard.append(deck[indices[i]])
            }
            evaluateAll(board: fullBoard, wins: &wins, ties: &ties, tieScratch: &tieScratch)
        }
        return samples
    }

    private func adaptiveMonteCarloSamples(cardsToDeal: Int) -> Int {
        // Keep total 5-card hand evaluations roughly bounded as table complexity rises.
        let combosPerHand: Int
        switch gameType {
        case .nlh:
            combosPerHand = Self.nlhFiveFromSevenCombos.count // 21
        case .plo:
            combosPerHand = Self.ploHandTwoCombos.count * Self.ploBoardThreeCombos.count // 60
        }

        let evalsPerSample = max(1, hands.count * combosPerHand)
        let targetEvaluations = cardsToDeal == 5 ? 3_000_000 : 2_000_000
        let scaledSamples = targetEvaluations / evalsPerSample
        return max(10_000, min(Self.monteCarloSamples, scaledSamples))
    }

    private func enumerateCombinations(n: Int, k: Int, start: Int, depth: Int, combo: inout [Int], block: ([Int]) -> Void) {
        if depth == k {
            block(combo)
            return
        }
        for i in start..<(n - k + depth + 1) {
            combo[depth] = i
            enumerateCombinations(n: n, k: k, start: i + 1, depth: depth + 1, combo: &combo, block: block)
        }
    }

    private func evaluateAll(board: [PlayingCard], wins: inout [Int], ties: inout [Double], tieScratch: inout [Int]) {
        var bestRank: UInt64 = 0
        var tieCount = 0

        for (idx, hand) in hands.enumerated() {
            let rank = bestHandRank(hand: hand, board: board)
            if tieCount == 0 || rank > bestRank {
                bestRank = rank
                tieScratch[0] = idx
                tieCount = 1
            } else if rank == bestRank {
                tieScratch[tieCount] = idx
                tieCount += 1
            }
        }

        if tieCount == 1 {
            wins[tieScratch[0]] += 1
            return
        }
        let share = 1.0 / Double(tieCount)
        for i in 0..<tieCount {
            ties[tieScratch[i]] += share
        }
    }

    private func bestHandRank(hand: [PlayingCard], board: [PlayingCard]) -> UInt64 {
        switch gameType {
        case .nlh:
            return bestFiveFromSeven(hand: hand, board: board)
        case .plo:
            return bestOmahaHand(hand: hand, board: board)
        }
    }

    private func bestFiveFromSeven(hand: [PlayingCard], board: [PlayingCard]) -> UInt64 {
        let h0 = hand[0], h1 = hand[1]
        let b0 = board[0], b1 = board[1], b2 = board[2], b3 = board[3], b4 = board[4]
        var best: UInt64 = 0
        for c in Self.nlhFiveFromSevenCombos {
            let r = HandEvaluator.rank(
                cardFromSeven(index: c.0, h0, h1, b0, b1, b2, b3, b4),
                cardFromSeven(index: c.1, h0, h1, b0, b1, b2, b3, b4),
                cardFromSeven(index: c.2, h0, h1, b0, b1, b2, b3, b4),
                cardFromSeven(index: c.3, h0, h1, b0, b1, b2, b3, b4),
                cardFromSeven(index: c.4, h0, h1, b0, b1, b2, b3, b4)
            )
            if r > best { best = r }
        }
        return best
    }

    private func bestOmahaHand(hand: [PlayingCard], board: [PlayingCard]) -> UInt64 {
        var best: UInt64 = 0
        for hc in Self.ploHandTwoCombos {
            for bc in Self.ploBoardThreeCombos {
                let r = HandEvaluator.rank(
                    hand[hc.0],
                    hand[hc.1],
                    board[bc.0],
                    board[bc.1],
                    board[bc.2]
                )
                if r > best { best = r }
            }
        }
        return best
    }

    @inline(__always)
    private func cardFromSeven(index: Int, _ h0: PlayingCard, _ h1: PlayingCard, _ b0: PlayingCard, _ b1: PlayingCard, _ b2: PlayingCard, _ b3: PlayingCard, _ b4: PlayingCard) -> PlayingCard {
        switch index {
        case 0: return h0
        case 1: return h1
        case 2: return b0
        case 3: return b1
        case 4: return b2
        case 5: return b3
        default: return b4
        }
    }

    private static func makeFiveIndexCombinations(n: Int) -> [FiveIndexCombo] {
        var result: [FiveIndexCombo] = []
        result.reserveCapacity(21)
        for a in 0..<(n - 4) {
            for b in (a + 1)..<(n - 3) {
                for c in (b + 1)..<(n - 2) {
                    for d in (c + 1)..<(n - 1) {
                        for e in (d + 1)..<n {
                            result.append((a, b, c, d, e))
                        }
                    }
                }
            }
        }
        return result
    }

    private static func makeTwoIndexCombinations(n: Int) -> [TwoIndexCombo] {
        var result: [TwoIndexCombo] = []
        result.reserveCapacity(n * (n - 1) / 2)
        for a in 0..<(n - 1) {
            for b in (a + 1)..<n {
                result.append((a, b))
            }
        }
        return result
    }

    private static func makeThreeIndexCombinations(n: Int) -> [ThreeIndexCombo] {
        var result: [ThreeIndexCombo] = []
        result.reserveCapacity(n * (n - 1) * (n - 2) / 6)
        for a in 0..<(n - 2) {
            for b in (a + 1)..<(n - 1) {
                for c in (b + 1)..<n {
                    result.append((a, b, c))
                }
            }
        }
        return result
    }
}
