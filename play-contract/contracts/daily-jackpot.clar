;; Daily Jackpot Contract
;; Progressive jackpot that accumulates from bets and pays out daily

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u500))
(define-constant err-jackpot-not-ready (err u501))
(define-constant err-no-entries (err u502))
(define-constant err-insufficient-balance (err u503))
(define-constant err-invalid-amount (err u504))

;; Jackpot contribution (1% of each bet)
(define-constant jackpot-percentage u1)
(define-constant percentage-divisor u100)

;; Blocks per day (approximately 144 blocks = 24 hours on Stacks)
(define-constant blocks-per-day u144)

;; Minimum bet to enter jackpot
(define-constant min-jackpot-entry u5000000) ;; 5 STX

;; Data Maps
(define-map jackpot-entries
    { day: uint, entry-id: uint }
    { player: principal, tickets: uint }
)

(define-map player-daily-tickets
    { player: principal, day: uint }
    uint
)

(define-map daily-jackpot-winners
    uint ;; day number
    { winner: principal, amount: uint, block: uint }
)

(define-map authorized-games principal bool)

;; Data Variables
(define-data-var current-jackpot uint u0)
(define-data-var jackpot-start-block uint u0)
(define-data-var current-day uint u0)
(define-data-var total-entries-today uint u0)
(define-data-var total-jackpots-paid uint u0)

;; Initialize start block
(begin
    (var-set jackpot-start-block block-height)
)

;; Read-only functions
(define-read-only (get-current-jackpot)
    (var-get current-jackpot)
)

(define-read-only (get-current-day)
    (/ (- block-height (var-get jackpot-start-block)) blocks-per-day)
)

(define-read-only (is-jackpot-ready)
    (> (get-current-day) (var-get current-day))
)

(define-read-only (get-player-tickets (player principal))
    (default-to u0 (map-get? player-daily-tickets { player: player, day: (get-current-day) }))
)

(define-read-only (get-jackpot-winner (day uint))
    (map-get? daily-jackpot-winners day)
)

(define-read-only (calculate-jackpot-contribution (bet-amount uint))
    (/ (* bet-amount jackpot-percentage) percentage-divisor)
)

(define-read-only (get-total-entries)
    (var-get total-entries-today)
)

(define-read-only (blocks-until-draw)
    (let
        (
            (day-end-block (+ (var-get jackpot-start-block) (* (+ (var-get current-day) u1) blocks-per-day)))
        )
        (if (> day-end-block block-height)
            (- day-end-block block-height)
            u0
        )
    )
)

(define-read-only (is-game-authorized (game principal))
    (default-to false (map-get? authorized-games game))
)

;; Private functions
(define-private (simple-random (max uint))
    (let
        (
            (vrf-seed (unwrap! (get-block-info? vrf-seed (- block-height u1)) u0))
            (seed-slice (unwrap-panic (as-max-len? vrf-seed u16)))
            (random-uint (buff-to-uint-le seed-slice))
        )
        (mod random-uint max)
    )
)

;; Public functions
(define-public (authorize-game (game principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (map-set authorized-games game true))
    )
)

(define-public (fund-jackpot (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set current-jackpot (+ (var-get current-jackpot) amount))
        (ok true)
    )
)

(define-public (add-jackpot-entry (player principal) (bet-amount uint))
    (begin
        (asserts! (is-game-authorized contract-caller) err-not-authorized)
        
        (let
            (
                (contribution (calculate-jackpot-contribution bet-amount))
                (day (get-current-day))
                (tickets (if (>= bet-amount min-jackpot-entry) u1 u0))
            )
            
            ;; Add contribution to jackpot
            (var-set current-jackpot (+ (var-get current-jackpot) contribution))
            
            ;; Add tickets if eligible
            (if (> tickets u0)
                (begin
                    (map-set player-daily-tickets
                        { player: player, day: day }
                        (+ (get-player-tickets player) tickets)
                    )
                    
                    (map-set jackpot-entries
                        { day: day, entry-id: (var-get total-entries-today) }
                        { player: player, tickets: tickets }
                    )
                    
                    (var-set total-entries-today (+ (var-get total-entries-today) u1))
                    (ok { contributed: contribution, tickets: tickets })
                )
                (ok { contributed: contribution, tickets: u0 })
            )
        )
    )
)

(define-public (draw-jackpot)
    (begin
        (asserts! (is-jackpot-ready) err-jackpot-not-ready)
        (asserts! (> (var-get total-entries-today) u0) err-no-entries)
        
        (let
            (
                (old-day (var-get current-day))
                (winner-index (simple-random (var-get total-entries-today)))
                (winner-entry (unwrap! (map-get? jackpot-entries { day: old-day, entry-id: winner-index }) err-no-entries))
                (winner (get player winner-entry))
                (prize (var-get current-jackpot))
            )
            
            ;; Pay winner
            (try! (as-contract (stx-transfer? prize tx-sender winner)))
            
            ;; Record winner
            (map-set daily-jackpot-winners old-day
                { winner: winner, amount: prize, block: block-height }
            )
            
            ;; Reset for new day
            (var-set current-day (get-current-day))
            (var-set total-entries-today u0)
            (var-set current-jackpot u0)
            (var-set total-jackpots-paid (+ (var-get total-jackpots-paid) u1))
            
            (ok { winner: winner, amount: prize })
        )
    )
)
