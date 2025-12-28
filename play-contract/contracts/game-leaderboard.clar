;; Game Leaderboard Contract
;; Tracks player statistics, rankings, and achievements

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u300))
(define-constant err-player-not-found (err u301))
(define-constant err-invalid-amount (err u302))

;; Data Maps
(define-map player-stats
    principal
    {
        total-games: uint,
        total-wins: uint,
        total-losses: uint,
        total-wagered: uint,
        total-winnings: uint,
        biggest-win: uint,
        win-streak: uint,
        best-streak: uint,
        last-game-block: uint
    }
)

(define-map authorized-games principal bool)

(define-map top-players
    uint ;; rank position (0-99 for top 100)
    { player: principal, score: uint }
)

;; Data Variables
(define-data-var total-players uint u0)
(define-data-var total-games-tracked uint u0)

;; Read-only functions
(define-read-only (get-player-stats (player principal))
    (default-to
        {
            total-games: u0,
            total-wins: u0,
            total-losses: u0,
            total-wagered: u0,
            total-winnings: u0,
            biggest-win: u0,
            win-streak: u0,
            best-streak: u0,
            last-game-block: u0
        }
        (map-get? player-stats player)
    )
)

(define-read-only (get-win-rate (player principal))
    (let
        (
            (stats (get-player-stats player))
            (total (get total-games stats))
            (wins (get total-wins stats))
        )
        (if (> total u0)
            (/ (* wins u10000) total) ;; Win rate in basis points (e.g., 5000 = 50%)
            u0
        )
    )
)

(define-read-only (get-total-profit (player principal))
    (let
        (
            (stats (get-player-stats player))
        )
        (if (>= (get total-winnings stats) (get total-wagered stats))
            (- (get total-winnings stats) (get total-wagered stats))
            u0
        )
    )
)

(define-read-only (get-top-player (rank uint))
    (map-get? top-players rank)
)

(define-read-only (get-total-players)
    (var-get total-players)
)

(define-read-only (is-game-authorized (game principal))
    (default-to false (map-get? authorized-games game))
)

;; Public functions
(define-public (authorize-game (game principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (map-set authorized-games game true))
    )
)

(define-public (record-game (player principal) (bet-amount uint) (won bool) (payout uint))
    (begin
        (asserts! (is-game-authorized contract-caller) err-not-authorized)
        
        (let
            (
                (current-stats (get-player-stats player))
                (is-new-player (is-eq (get total-games current-stats) u0))
                (new-wins (if won (+ (get total-wins current-stats) u1) (get total-wins current-stats)))
                (new-losses (if won (get total-losses current-stats) (+ (get total-losses current-stats) u1)))
                (new-streak (if won (+ (get win-streak current-stats) u1) u0))
                (new-best-streak (if (> new-streak (get best-streak current-stats)) new-streak (get best-streak current-stats)))
                (new-biggest-win (if (and won (> payout (get biggest-win current-stats))) payout (get biggest-win current-stats)))
            )
            
            ;; Update player stats
            (map-set player-stats player
                {
                    total-games: (+ (get total-games current-stats) u1),
                    total-wins: new-wins,
                    total-losses: new-losses,
                    total-wagered: (+ (get total-wagered current-stats) bet-amount),
                    total-winnings: (+ (get total-winnings current-stats) payout),
                    biggest-win: new-biggest-win,
                    win-streak: new-streak,
                    best-streak: new-best-streak,
                    last-game-block: block-height
                }
            )
            
            ;; Increment total players if new
            (if is-new-player
                (var-set total-players (+ (var-get total-players) u1))
                true
            )
            
            ;; Increment total games
            (var-set total-games-tracked (+ (var-get total-games-tracked) u1))
            
            (ok true)
        )
    )
)
