;; Game Treasury Contract
;; Manages the prize pool and payouts for the card flip game

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))

;; Data Variables
(define-data-var treasury-balance uint u0)
(define-data-var total-games-played uint u0)
(define-data-var total-payouts uint u0)

;; Data Maps
(define-map authorized-games principal bool)

;; Read-only functions
(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

(define-read-only (get-total-games)
    (var-get total-games-played)
)

(define-read-only (get-total-payouts)
    (var-get total-payouts)
)

(define-read-only (is-game-authorized (game principal))
    (default-to false (map-get? authorized-games game))
)

;; Public functions
(define-public (authorize-game (game principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-games game true))
    )
)

(define-public (revoke-game (game principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-delete authorized-games game))
    )
)

(define-public (deposit-to-treasury (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-public (process-game-bet (player principal) (bet-amount uint))
    (begin
        (asserts! (is-game-authorized contract-caller) err-owner-only)
        (asserts! (> bet-amount u0) err-invalid-amount)
        (var-set treasury-balance (+ (var-get treasury-balance) bet-amount))
        (var-set total-games-played (+ (var-get total-games-played) u1))
        (ok true)
    )
)

(define-public (process-payout (winner principal) (payout-amount uint))
    (begin
        (asserts! (is-game-authorized contract-caller) err-owner-only)
        (asserts! (>= (var-get treasury-balance) payout-amount) err-insufficient-balance)
        (try! (as-contract (stx-transfer? payout-amount tx-sender winner)))
        (var-set treasury-balance (- (var-get treasury-balance) payout-amount))
        (var-set total-payouts (+ (var-get total-payouts) payout-amount))
        (ok true)
    )
)

(define-public (withdraw-treasury (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= amount (var-get treasury-balance)) err-insufficient-balance)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set treasury-balance (- (var-get treasury-balance) amount))
        (ok true)
    )
)
