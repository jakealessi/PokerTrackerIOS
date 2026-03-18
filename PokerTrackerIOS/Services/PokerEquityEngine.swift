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
    case nlh   // 2 cards per hand
    case plo   // 4 cards per hand
    case plo5  // 5 cards per hand

    var cardsPerHand: Int {
        switch self {
        case .nlh: return 2
        case .plo: return 4
        case .plo5: return 5
        }
    }
}

// MARK: - Equity Result

struct EquityResult {
    let wins: [Int]      // per hand
    let ties: [Double]   // per hand (fractional: 1/n per tied runout)
    let totalRunouts: Int

    func winPercent(forHand i: Int) -> Double {
        guard totalRunouts > 0, wins.indices.contains(i) else { return 0 }
        return Double(wins[i]) / Double(totalRunouts) * 100
    }

    func tiePercent(forHand i: Int) -> Double {
        guard totalRunouts > 0, ties.indices.contains(i) else { return 0 }
        return ties[i] / Double(totalRunouts) * 100
    }
}

// MARK: - Hand Evaluator (5-card)

struct HandEvaluator {
    /// Returns a comparable value; higher = better hand
    static func rank(_ five: [PlayingCard]) -> UInt64 {
        guard five.count == 5 else { return 0 }
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

    /// Fixed Monte Carlo budget. If exact has to process more runouts than this,
    /// Monte Carlo is usually the cheaper path.
    private static let monteCarloSamples = 100_000
    /// Adaptive MC settings: run in batches, stop early once precision is good enough.
    private static let monteCarloMinSamples = 25_000
    private static let monteCarloBatchSize = 10_000
    private static let monteCarloChunkSize = 2_500
    private static let monteCarloConfidenceZ = 1.96
    private static let monteCarloTargetHalfWidthPercent = 0.30
    private typealias FiveIndexCombo = (Int, Int, Int, Int, Int)
    private typealias TwoIndexCombo = (Int, Int)
    private typealias ThreeIndexCombo = (Int, Int, Int)
    private static let nlhFiveFromSevenCombos = makeFiveIndexCombinations(n: 7)
    private static let ploHandTwoCombos = makeTwoIndexCombinations(n: 4)
    private static let plo5HandTwoCombos = makeTwoIndexCombinations(n: 5)
    private static let ploBoardThreeCombos = makeThreeIndexCombinations(n: 5)

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func nextUInt64() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextInt(upperBound: Int) -> Int {
            guard upperBound > 0 else { return 0 }
            let bound = UInt64(upperBound)
            let threshold = (UInt64.max - bound + 1) % bound
            while true {
                let r = nextUInt64()
                if r >= threshold { return Int(r % bound) }
            }
        }
    }

    func calculate() -> EquityResult? {
        guard board.count <= 5 else { return nil }
        guard hands.count >= 2 else { return nil }
        guard hands.allSatisfy({ $0.count == gameType.cardsPerHand }) else { return nil }

        let allKnownCards = hands.flatMap { $0 } + board + deadCards
        let used = Set(allKnownCards)
        guard used.count == allKnownCards.count else { return nil }

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
            let useMonteCarlo = shouldUseMonteCarlo(cardsToDeal: cardsToDeal, deckCount: deck.count)
            if !useMonteCarlo {
                total = runExactEnumerated(deck: deck, cardsToDeal: cardsToDeal, wins: &wins, ties: &ties)
            } else {
                // Monte Carlo is cheaper once exact would exceed the fixed runout budget.
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

    private func shouldUseMonteCarlo(cardsToDeal: Int, deckCount: Int) -> Bool {
        let totalRunouts = countCombinations(n: deckCount, k: cardsToDeal)
        return totalRunouts > Double(Self.monteCarloSamples)
    }

    private func runExactEnumerated(deck: [PlayingCard], cardsToDeal: Int, wins: inout [Int], ties: inout [Double]) -> Int {
        let firstChoiceCount = deck.count - cardsToDeal + 1
        let chunkCount = max(1, firstChoiceCount)

        if chunkCount == 1 {
            return runExactChunk(
                deck: deck,
                cardsToDeal: cardsToDeal,
                firstChoiceRange: 0..<firstChoiceCount,
                wins: &wins,
                ties: &ties
            )
        }

        let lock = NSLock()
        var total = 0

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            var localWins = Array(repeating: 0, count: hands.count)
            var localTies = Array(repeating: 0.0, count: hands.count)
            let localTotal = runExactChunk(
                deck: deck,
                cardsToDeal: cardsToDeal,
                firstChoiceRange: chunkIndex..<(chunkIndex + 1),
                wins: &localWins,
                ties: &localTies
            )

            lock.lock()
            total += localTotal
            for handIndex in wins.indices {
                wins[handIndex] += localWins[handIndex]
                ties[handIndex] += localTies[handIndex]
            }
            lock.unlock()
        }

        return total
    }

    private func runExactChunk(
        deck: [PlayingCard],
        cardsToDeal: Int,
        firstChoiceRange: Range<Int>,
        wins: inout [Int],
        ties: inout [Double]
    ) -> Int {
        var tieScratch = Array(repeating: 0, count: hands.count)
        var fullBoard = board
        fullBoard.reserveCapacity(5)
        var combo = Array(repeating: 0, count: cardsToDeal)
        var total = 0

        for firstChoice in firstChoiceRange {
            combo[0] = firstChoice
            enumerateCombinations(
                n: deck.count,
                k: cardsToDeal,
                start: firstChoice + 1,
                depth: 1,
                combo: &combo
            ) { runoutIndices in
                if fullBoard.count > board.count {
                    fullBoard.removeLast(fullBoard.count - board.count)
                }
                for i in 0..<cardsToDeal {
                    fullBoard.append(deck[runoutIndices[i]])
                }
                evaluateAll(board: fullBoard, wins: &wins, ties: &ties, tieScratch: &tieScratch)
                total += 1
            }
        }

        return total
    }

    private func runMonteCarlo(deck: [PlayingCard], cardsToDeal: Int, wins: inout [Int], ties: inout [Double]) -> Int {
        let maxSamples = min(Self.monteCarloSamples, Int(countCombinations(n: deck.count, k: cardsToDeal)))
        let minimumSamples = min(maxSamples, Self.monteCarloMinSamples)
        let baseSeed = monteCarloSeed(cardsToDeal: cardsToDeal)
        var tieSquares = Array(repeating: 0.0, count: hands.count)
        var processed = 0

        while processed < maxSamples {
            let batchSamples = min(Self.monteCarloBatchSize, maxSamples - processed)
            runMonteCarloBatch(
                deck: deck,
                cardsToDeal: cardsToDeal,
                sampleOffset: processed,
                sampleCount: batchSamples,
                baseSeed: baseSeed,
                wins: &wins,
                ties: &ties,
                tieSquares: &tieSquares
            )
            processed += batchSamples

            if processed >= minimumSamples,
               hasMonteCarloConverged(sampleCount: processed, wins: wins, ties: ties, tieSquares: tieSquares) {
                break
            }
        }

        return processed
    }

    private func runMonteCarloBatch(
        deck: [PlayingCard],
        cardsToDeal: Int,
        sampleOffset: Int,
        sampleCount: Int,
        baseSeed: UInt64,
        wins: inout [Int],
        ties: inout [Double],
        tieSquares: inout [Double]
    ) {
        let chunkCount = max(1, (sampleCount + Self.monteCarloChunkSize - 1) / Self.monteCarloChunkSize)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunkIndex in
            let chunkStart = chunkIndex * Self.monteCarloChunkSize
            let chunkSamples = min(Self.monteCarloChunkSize, sampleCount - chunkStart)
            guard chunkSamples > 0 else { return }

            var localWins = Array(repeating: 0, count: hands.count)
            var localTies = Array(repeating: 0.0, count: hands.count)
            var localTieSquares = Array(repeating: 0.0, count: hands.count)
            var indices = Array(0..<deck.count)
            var tieScratch = Array(repeating: 0, count: hands.count)
            var fullBoard = board
            fullBoard.reserveCapacity(5)
            var rng = SplitMix64(
                seed: mixedSeed(baseSeed, salt: UInt64(sampleOffset + chunkStart + 1))
            )

            for _ in 0..<chunkSamples {
                for i in 0..<cardsToDeal {
                    let j = i + rng.nextInt(upperBound: deck.count - i)
                    indices.swapAt(i, j)
                }
                if fullBoard.count > board.count {
                    fullBoard.removeLast(fullBoard.count - board.count)
                }
                for i in 0..<cardsToDeal {
                    fullBoard.append(deck[indices[i]])
                }
                evaluateAllWithMoments(
                    board: fullBoard,
                    wins: &localWins,
                    ties: &localTies,
                    tieSquares: &localTieSquares,
                    tieScratch: &tieScratch
                )
            }

            lock.lock()
            for handIndex in wins.indices {
                wins[handIndex] += localWins[handIndex]
                ties[handIndex] += localTies[handIndex]
                tieSquares[handIndex] += localTieSquares[handIndex]
            }
            lock.unlock()
        }
    }

    private func hasMonteCarloConverged(
        sampleCount: Int,
        wins: [Int],
        ties: [Double],
        tieSquares: [Double]
    ) -> Bool {
        let n = Double(sampleCount)
        guard n > 0 else { return false }

        for handIndex in wins.indices {
            let winMean = Double(wins[handIndex]) / n
            let winVariance = max(0, winMean * (1 - winMean))

            let tieMean = ties[handIndex] / n
            let tieSecondMoment = tieSquares[handIndex] / n
            let tieVariance = max(0, tieSecondMoment - tieMean * tieMean)

            let equityMean = (Double(wins[handIndex]) + ties[handIndex]) / n
            let equitySecondMoment = (Double(wins[handIndex]) + tieSquares[handIndex]) / n
            let equityVariance = max(0, equitySecondMoment - equityMean * equityMean)

            if confidenceHalfWidthPercent(variance: winVariance, sampleCount: n) > Self.monteCarloTargetHalfWidthPercent {
                return false
            }
            if confidenceHalfWidthPercent(variance: tieVariance, sampleCount: n) > Self.monteCarloTargetHalfWidthPercent {
                return false
            }
            if confidenceHalfWidthPercent(variance: equityVariance, sampleCount: n) > Self.monteCarloTargetHalfWidthPercent {
                return false
            }
        }

        return true
    }

    private func confidenceHalfWidthPercent(variance: Double, sampleCount: Double) -> Double {
        guard sampleCount > 0 else { return .infinity }
        return Self.monteCarloConfidenceZ * sqrt(variance / sampleCount) * 100
    }

    private func mixedSeed(_ baseSeed: UInt64, salt: UInt64) -> UInt64 {
        var value = baseSeed ^ (salt &* 0x9E3779B97F4A7C15)
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value &*= 0x94D049BB133111EB
        value ^= value >> 31
        return value == 0 ? 0x9E3779B97F4A7C15 : value
    }

    private func monteCarloSeed(cardsToDeal: Int) -> UInt64 {
        var seed: UInt64 = 0xcbf29ce484222325
        @inline(__always)
        func cardCode(_ card: PlayingCard) -> UInt64 {
            let suit: UInt64
            switch card.suit {
            case .spades: suit = 0
            case .hearts: suit = 1
            case .diamonds: suit = 2
            case .clubs: suit = 3
            }
            return (UInt64(card.rank.rawValue) << 2) | suit
        }
        @inline(__always)
        func mix(_ value: UInt64, into seed: inout UInt64) {
            seed ^= value
            seed &*= 0x100000001b3
        }

        mix(UInt64(gameType.cardsPerHand), into: &seed)
        mix(UInt64(cardsToDeal), into: &seed)
        mix(UInt64(hands.count), into: &seed)
        for hand in hands {
            mix(UInt64(hand.count), into: &seed)
            for card in hand {
                mix(cardCode(card), into: &seed)
            }
        }
        mix(UInt64(board.count), into: &seed)
        for card in board {
            mix(cardCode(card), into: &seed)
        }
        mix(UInt64(deadCards.count), into: &seed)
        for card in deadCards {
            mix(cardCode(card), into: &seed)
        }
        return seed
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

    private func evaluateAllWithMoments(
        board: [PlayingCard],
        wins: inout [Int],
        ties: inout [Double],
        tieSquares: inout [Double],
        tieScratch: inout [Int]
    ) {
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
        let shareSquared = share * share
        for i in 0..<tieCount {
            let handIndex = tieScratch[i]
            ties[handIndex] += share
            tieSquares[handIndex] += shareSquared
        }
    }

    private func bestHandRank(hand: [PlayingCard], board: [PlayingCard]) -> UInt64 {
        switch gameType {
        case .nlh:
            return bestFiveFromSeven(hand: hand, board: board)
        case .plo:
            return bestOmahaHand(hand: hand, board: board)
        case .plo5:
            return bestOmaha5Hand(hand: hand, board: board)
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

    private func bestOmaha5Hand(hand: [PlayingCard], board: [PlayingCard]) -> UInt64 {
        var best: UInt64 = 0
        for hc in Self.plo5HandTwoCombos {
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
