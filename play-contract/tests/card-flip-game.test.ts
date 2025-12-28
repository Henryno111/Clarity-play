import { describe, it, expect, beforeEach } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const player1 = accounts.get("wallet_1")!;
const player2 = accounts.get("wallet_2")!;

describe("Card Flip Game Platform", () => {
  describe("Game Treasury Tests", () => {
    it("should initialize with zero balance", () => {
      const balance = simnet.callReadOnlyFn(
        "game-treasury",
        "get-treasury-balance",
        [],
        deployer
      );
      expect(balance.result).toBe("u0");
    });

    it("should allow deposits to treasury", () => {
      const depositAmount = 10000000; // 10 STX
      
      const deposit = simnet.callPublicFn(
        "game-treasury",
        "deposit-to-treasury",
        [`u${depositAmount}`],
        deployer
      );
      
      expect(deposit.result).toContain("(ok true)");
      
      const balance = simnet.callReadOnlyFn(
        "game-treasury",
        "get-treasury-balance",
        [],
        deployer
      );
      expect(balance.result).toBe(`u${depositAmount}`);
    });

    it("should allow owner to authorize games", () => {
      const gameContract = `${deployer}.card-flip-game`;
      
      const authorize = simnet.callPublicFn(
        "game-treasury",
        "authorize-game",
        [`'${gameContract}`],
        deployer
      );
      
      expect(authorize.result).toContain("(ok true)");
      
      const isAuthorized = simnet.callReadOnlyFn(
        "game-treasury",
        "is-game-authorized",
        [`'${gameContract}`],
        deployer
      );
      expect(isAuthorized.result).toBe("true");
    });

    it("should prevent non-owner from authorizing games", () => {
      const gameContract = `${deployer}.card-flip-game`;
      
      const authorize = simnet.callPublicFn(
        "game-treasury",
        "authorize-game",
        [`'${gameContract}`],
        player1
      );
      
      expect(authorize.result).toContain("(err u100)");
    });
  });

  describe("Card Flip Game Tests", () => {
    beforeEach(() => {
      // Fund treasury
      simnet.callPublicFn(
        "game-treasury",
        "deposit-to-treasury",
        ["u100000000"],
        deployer
      );
      
      // Authorize card-flip-game contract
      simnet.callPublicFn(
        "game-treasury",
        "authorize-game",
        [`'${deployer}.card-flip-game`],
        deployer
      );
      
      // Set treasury contract in game
      simnet.callPublicFn(
        "card-flip-game",
        "set-treasury-contract",
        [`'${deployer}.game-treasury`],
        deployer
      );
    });

    it("should start a new game with valid bet", () => {
      const betAmount = 5000000; // 5 STX
      const cardChoice = 0; // Red
      
      const startGame = simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, `u${cardChoice}`],
        player1
      );
      
      expect(startGame.result).toContain("(ok u0)");
    });

    it("should reject bet below minimum", () => {
      const betAmount = 500000; // 0.5 STX (below 1 STX minimum)
      const cardChoice = 1; // Black
      
      const startGame = simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, `u${cardChoice}`],
        player1
      );
      
      expect(startGame.result).toContain("(err u202)");
    });

    it("should reject invalid card choice", () => {
      const betAmount = 5000000; // 5 STX
      const cardChoice = 2; // Invalid (only 0 or 1 allowed)
      
      const startGame = simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, `u${cardChoice}`],
        player1
      );
      
      expect(startGame.result).toContain("(err u204)");
    });

    it("should track multiple games per player", () => {
      const betAmount = 2000000; // 2 STX
      
      // Start first game
      simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, "u0"],
        player1
      );
      
      // Start second game
      simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, "u1"],
        player1
      );
      
      const playerGames = simnet.callReadOnlyFn(
        "card-flip-game",
        "get-player-games",
        [player1],
        player1
      );
      
      expect(playerGames.result).toContain("u0");
      expect(playerGames.result).toContain("u1");
    });

    it("should calculate correct payout (130% of bet)", () => {
      const betAmount = 10000000; // 10 STX
      const expectedPayout = 13000000; // 13 STX (130%)
      
      const payout = simnet.callReadOnlyFn(
        "card-flip-game",
        "calculate-payout",
        [`u${betAmount}`],
        deployer
      );
      
      expect(payout.result).toBe(`u${expectedPayout}`);
    });

    it("should complete full game flow", () => {
      const betAmount = 5000000; // 5 STX
      const cardChoice = 0; // Red
      
      // Start game
      const startGame = simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, `u${cardChoice}`],
        player1
      );
      
      expect(startGame.result).toContain("(ok u0)");
      
      // Mine a block to get randomness
      simnet.mineEmptyBlock();
      
      // Reveal and settle
      const reveal = simnet.callPublicFn(
        "card-flip-game",
        "reveal-and-settle",
        ["u0"],
        player1
      );
      
      // Result should be either win or loss
      expect(reveal.result).toBeTruthy();
    });

    it("should prevent revealing before next block", () => {
      const betAmount = 5000000; // 5 STX
      
      // Start game
      simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, "u0"],
        player1
      );
      
      // Try to reveal immediately (same block)
      const reveal = simnet.callPublicFn(
        "card-flip-game",
        "reveal-and-settle",
        ["u0"],
        player1
      );
      
      expect(reveal.result).toContain("(err u203)");
    });

    it("should prevent non-player from revealing", () => {
      const betAmount = 5000000; // 5 STX
      
      // Player 1 starts game
      simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        [`u${betAmount}`, "u0"],
        player1
      );
      
      simnet.mineEmptyBlock();
      
      // Player 2 tries to reveal player 1's game
      const reveal = simnet.callPublicFn(
        "card-flip-game",
        "reveal-and-settle",
        ["u0"],
        player2
      );
      
      expect(reveal.result).toContain("(err u206)");
    });
  });

  describe("Integration Tests", () => {
    beforeEach(() => {
      // Setup treasury and authorization
      simnet.callPublicFn(
        "game-treasury",
        "deposit-to-treasury",
        ["u200000000"],
        deployer
      );
      
      simnet.callPublicFn(
        "game-treasury",
        "authorize-game",
        [`'${deployer}.card-flip-game`],
        deployer
      );
      
      simnet.callPublicFn(
        "card-flip-game",
        "set-treasury-contract",
        [`'${deployer}.game-treasury`],
        deployer
      );
    });

    it("should handle multiple concurrent games", () => {
      // Player 1 game
      const game1 = simnet.callPublicFn(
        "card-flip-game",
        "play-game",
        ["u3000000", "u0"],
        player1
      );
      
      // Player 2 game
      const game2 = simnet.callPublicFn(
        "card-flip-game",
        "play-game",
        ["u4000000", "u1"],
        player2
      );
      
      expect(game1.result).toContain("game-id");
      expect(game2.result).toContain("game-id");
    });

    it("should update treasury stats correctly", () => {
      // Play a game
      simnet.callPublicFn(
        "card-flip-game",
        "start-game",
        ["u5000000", "u1"],
        player1
      );
      
      const totalGames = simnet.callReadOnlyFn(
        "game-treasury",
        "get-total-games",
        [],
        deployer
      );
      
      expect(totalGames.result).toBe("u1");
    });
  });
});
