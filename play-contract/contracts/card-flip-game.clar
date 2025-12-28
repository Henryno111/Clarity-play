;; Card Flip Game Contract
;; Interactive card flip game where players bet STX and win 30% profit if they guess correctly

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-game-not-found (err u200))
(define-constant err-game-already-exists (err u201))
(define-constant err-invalid-bet (err u202))
(define-constant err-game-already-played (err u203))
(define-constant err-invalid-card (err u204))
(define-constant err-treasury-error (err u205))
(define-constant err-not-player (err u206))

;; Minimum and maximum bet amounts (in microSTX)
(define-constant min-bet u1000000) ;; 1 STX
(define-constant max-bet u100000000) ;; 100 STX

;; Win percentage (30% profit means player gets back 130% of bet)
(define-constant win-multiplier u130)
(define-constant divisor u100)

;; Card values (0 = Red, 1 = Black)
(define-constant card-red u0)
(define-constant card-black u1)

;; Game status
(define-constant status-pending u0)
(define-constant status-won u1)
(define-constant status-lost u2)

;; Data Maps
(define-map games
    { game-id: uint }
    {
        player: principal,
        bet-amount: uint,
        player-choice: uint,
        revealed-card: (optional uint),
        status: uint,
        block-height: uint,
        payout: uint
    }
)

(define-map player-games principal (list 100 uint))

;; Data Variables
(define-data-var game-nonce uint u0)
(define-data-var treasury-contract (optional principal) none)

;; Read-only functions
(define-read-only (get-game (game-id uint))
    (map-get? games { game-id: game-id })
)

(define-read-only (get-player-games (player principal))
    (default-to (list) (map-get? player-games player))
)

(define-read-only (get-next-game-id)
    (var-get game-nonce)
)

(define-read-only (calculate-payout (bet-amount uint))
    (/ (* bet-amount win-multiplier) divisor)
)

(define-read-only (get-treasury-contract)
    (var-get treasury-contract)
)

;; Private functions
(define-private (generate-random-card (game-id uint) (ref-block-height uint))
    ;; Simple pseudo-random generation using block hash and game-id
    ;; In production, consider using VRF or other secure randomness
    (let
        (
            (prev-block (- ref-block-height u1))
            (vrf-seed (unwrap! (get-block-info? vrf-seed prev-block) u0))
            (seed-slice (unwrap-panic (as-max-len? vrf-seed u16)))
            (hash-uint (buff-to-uint-le seed-slice))
            (combined (+ hash-uint game-id))
        )
        (mod combined u2) ;; Returns 0 or 1
    )
)

;; Public functions
(define-public (set-treasury-contract (treasury principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-player)
        (ok (var-set treasury-contract (some treasury)))
    )
)

(define-public (start-game (bet-amount uint) (card-choice uint))
    (let
        (
            (game-id (var-get game-nonce))
            (player tx-sender)
            (current-block block-height)
        )
        ;; Validate bet amount
        (asserts! (and (>= bet-amount min-bet) (<= bet-amount max-bet)) err-invalid-bet)
        
        ;; Validate card choice (0 = Red, 1 = Black)
        (asserts! (or (is-eq card-choice card-red) (is-eq card-choice card-black)) err-invalid-card)
        
        ;; Transfer bet to treasury
        (try! (stx-transfer? bet-amount tx-sender (as-contract tx-sender)))
        
        ;; Notify treasury of bet
        (unwrap! (match (var-get treasury-contract)
            treasury-addr (contract-call? .game-treasury process-game-bet player bet-amount)
            err-treasury-error
        ) err-treasury-error)
        
        ;; Create game record
        (map-set games
            { game-id: game-id }
            {
                player: player,
                bet-amount: bet-amount,
                player-choice: card-choice,
                revealed-card: none,
                status: status-pending,
                block-height: current-block,
                payout: u0
            }
        )
        
        ;; Add game to player's game history
        (match (map-get? player-games player)
            existing-games (map-set player-games player (unwrap-panic (as-max-len? (append existing-games game-id) u100)))
            (map-set player-games player (list game-id))
        )
        
        ;; Increment game nonce
        (var-set game-nonce (+ game-id u1))
        
        (ok game-id)
    )
)

(define-public (reveal-and-settle (game-id uint))
    (let
        (
            (game-data (unwrap! (map-get? games { game-id: game-id }) err-game-not-found))
            (player (get player game-data))
            (bet-amount (get bet-amount game-data))
            (player-choice (get player-choice game-data))
            (game-block (get block-height game-data))
            (current-block block-height)
        )
        ;; Ensure caller is the player
        (asserts! (is-eq tx-sender player) err-not-player)
        
        ;; Ensure game hasn't been played yet
        (asserts! (is-eq (get status game-data) status-pending) err-game-already-played)
        
        ;; Must wait at least 1 block for randomness
        (asserts! (> current-block game-block) err-game-already-played)
        
        (let
            (
                (revealed-card (generate-random-card game-id current-block))
                (is-winner (is-eq player-choice revealed-card))
                (payout-amount (if is-winner (calculate-payout bet-amount) u0))
                (new-status (if is-winner status-won status-lost))
            )
            ;; Update game with result
            (map-set games
                { game-id: game-id }
                (merge game-data {
                    revealed-card: (some revealed-card),
                    status: new-status,
                    payout: payout-amount
                })
            )
            
            ;; Process payout if winner
            (if is-winner
                (begin
                    (unwrap! (match (var-get treasury-contract)
                        treasury-addr (contract-call? .game-treasury process-payout player payout-amount)
                        err-treasury-error
                    ) err-treasury-error)
                    (ok { winner: true, card: revealed-card, payout: payout-amount })
                )
                (ok { winner: false, card: revealed-card, payout: u0 })
            )
        )
    )
)

(define-public (play-game (bet-amount uint) (card-choice uint))
    ;; Convenience function to start and immediately schedule reveal
    ;; Player must call reveal-and-settle in the next block
    (let
        (
            (game-id-response (try! (start-game bet-amount card-choice)))
        )
        (ok { 
            game-id: game-id-response,
            message: "Game started! Call reveal-and-settle in the next block to see result"
        })
    )
)
