# Card Flip Game Platform

An interactive blockchain-based card flip gambling game built on Stacks blockchain using Clarity smart contracts.

## 🎮 Game Overview

Players bet STX tokens on a card flip game where they choose between Red (0) or Black (1). If they win, they receive **30% profit** (130% of their bet back).

## 📋 Smart Contracts

### 1. **game-treasury.clar**
Manages the prize pool and handles all financial operations:
- Deposits and withdrawals
- Game authorization system
- Payout processing
- Treasury balance tracking

### 2. **card-flip-game.clar**
Main game logic for the card flip experience:
- Start games with bet amount and card choice
- Pseudo-random card generation using block hashes
- Automatic win/loss settlement
- Player game history tracking

## 🎯 How to Play

### Step 1: Start a Game
```clarity
(contract-call? .card-flip-game start-game u5000000 u0)
```
- `u5000000` = 5 STX bet
- `u0` = Red card (use `u1` for Black)

### Step 2: Wait for Next Block
The game requires waiting at least one block to ensure randomness.

### Step 3: Reveal and Settle
```clarity
(contract-call? .card-flip-game reveal-and-settle u0)
```
- `u0` = your game ID

### Alternative: One-Step Play
```clarity
(contract-call? .card-flip-game play-game u5000000 u0)
```
Returns game ID - you still need to call `reveal-and-settle` in the next block.

## 💰 Betting Rules

- **Minimum Bet**: 1 STX (1,000,000 microSTX)
- **Maximum Bet**: 100 STX (100,000,000 microSTX)
- **Win Payout**: 130% of bet amount (30% profit)
- **Loss**: Bet amount goes to treasury

## 🔧 Setup Instructions

### Prerequisites
- Clarinet CLI installed
- Node.js and npm

### Installation

1. Install dependencies:
```bash
npm install
```

2. Check contracts:
```bash
clarinet check
```

3. Run tests:
```bash
npm test
```

### Initialize Treasury

Before playing, the treasury needs to be funded and the game authorized:

```clarity
;; 1. Deposit to treasury (as deployer)
(contract-call? .game-treasury deposit-to-treasury u100000000)

;; 2. Authorize the game contract (as deployer)
(contract-call? .game-treasury authorize-game .card-flip-game)

;; 3. Set treasury in game contract (as deployer)
(contract-call? .card-flip-game set-treasury-contract .game-treasury)
```

## 📊 Read-Only Functions

### Game Contract
- `(get-game game-id)` - Get game details
- `(get-player-games player)` - Get all games for a player
- `(get-next-game-id)` - Get the next available game ID
- `(calculate-payout bet-amount)` - Calculate potential winnings

### Treasury Contract
- `(get-treasury-balance)` - Current treasury balance
- `(get-total-games)` - Total games played
- `(get-total-payouts)` - Total amount paid to winners
- `(is-game-authorized game)` - Check if a game is authorized

## 🎲 Game Mechanics

### Card Values
- `0` = Red Card
- `1` = Black Card

### Game Status
- `0` = Pending (awaiting reveal)
- `1` = Won
- `2` = Lost

### Randomness
The game uses block hash-based pseudo-randomness. For production, consider integrating with a VRF (Verifiable Random Function) oracle for enhanced security.

## 🧪 Testing

Run the test suite:
```bash
npm test
```

Test coverage includes:
- Treasury initialization and deposits
- Game authorization
- Starting games with various bet amounts
- Card choice validation
- Reveal and settlement logic
- Multi-player scenarios
- Payout calculations

## 🏗️ Architecture

```
┌─────────────────┐
│   Player        │
└────────┬────────┘
         │
         │ 1. Start Game (bet + choice)
         ▼
┌─────────────────────┐      ┌──────────────────┐
│  card-flip-game     │◄────►│  game-treasury   │
│  - Start game       │      │  - Hold funds    │
│  - Reveal & settle  │      │  - Process bets  │
│  - Track history    │      │  - Pay winners   │
└─────────────────────┘      └──────────────────┘
         │
         │ 2. Reveal (next block)
         ▼
┌─────────────────┐
│   Result        │
│  Win: +30%      │
│  Lose: -100%    │
└─────────────────┘
```

## ⚠️ Security Considerations

1. **Randomness**: Current implementation uses block hash for randomness. Consider VRF for production.
2. **Treasury Management**: Only owner can authorize games and withdraw funds.
3. **Game Integrity**: Players must wait for next block to prevent manipulation.
4. **Bet Limits**: Min/max limits prevent dust attacks and excessive losses.

## 📝 License

MIT

## 🚀 Future Enhancements

- [ ] VRF integration for true randomness
- [ ] Multi-card game variants
- [ ] Leaderboard system
- [ ] Referral rewards
- [ ] Progressive jackpots
- [ ] Game statistics dashboard
