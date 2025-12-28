;; Referral Rewards Contract
;; Manages referral system and bonus rewards for players

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u400))
(define-constant err-already-referred (err u401))
(define-constant err-self-referral (err u402))
(define-constant err-insufficient-balance (err u403))
(define-constant err-invalid-amount (err u404))

;; Referral rewards (5% of bet amount for referrer)
(define-constant referral-percentage u5)
(define-constant percentage-divisor u100)

;; Minimum bet to earn referral bonus
(define-constant min-referral-bet u1000000) ;; 1 STX

;; Data Maps
(define-map player-referrer principal principal)
(define-map referral-earnings principal uint)
(define-map referral-count principal uint)
(define-map authorized-games principal bool)

;; Data Variables
(define-data-var total-referrals uint u0)
(define-data-var total-rewards-paid uint u0)
(define-data-var rewards-pool uint u0)

;; Read-only functions
(define-read-only (get-referrer (player principal))
    (map-get? player-referrer player)
)

(define-read-only (get-referral-earnings (referrer principal))
    (default-to u0 (map-get? referral-earnings referrer))
)

(define-read-only (get-referral-count (referrer principal))
    (default-to u0 (map-get? referral-count referrer))
)

(define-read-only (calculate-referral-bonus (bet-amount uint))
    (if (>= bet-amount min-referral-bet)
        (/ (* bet-amount referral-percentage) percentage-divisor)
        u0
    )
)

(define-read-only (get-total-referrals)
    (var-get total-referrals)
)

(define-read-only (get-rewards-pool)
    (var-get rewards-pool)
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

(define-public (register-referral (referred-player principal) (referrer principal))
    (begin
        (asserts! (is-game-authorized contract-caller) err-not-authorized)
        (asserts! (not (is-eq referred-player referrer)) err-self-referral)
        (asserts! (is-none (map-get? player-referrer referred-player)) err-already-referred)
        
        ;; Set referrer
        (map-set player-referrer referred-player referrer)
        
        ;; Increment referral count
        (map-set referral-count referrer 
            (+ (default-to u0 (map-get? referral-count referrer)) u1)
        )
        
        ;; Increment total referrals
        (var-set total-referrals (+ (var-get total-referrals) u1))
        
        (ok true)
    )
)

(define-public (fund-rewards-pool (amount uint))
    (begin
        (asserts! (> amount u0) err-invalid-amount)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set rewards-pool (+ (var-get rewards-pool) amount))
        (ok true)
    )
)

(define-public (process-referral-bonus (player principal) (bet-amount uint))
    (begin
        (asserts! (is-game-authorized contract-caller) err-not-authorized)
        
        (match (map-get? player-referrer player)
            referrer (let
                (
                    (bonus (calculate-referral-bonus bet-amount))
                )
                (if (and (> bonus u0) (>= (var-get rewards-pool) bonus))
                    (begin
                        ;; Pay referral bonus
                        (try! (as-contract (stx-transfer? bonus tx-sender referrer)))
                        
                        ;; Update earnings
                        (map-set referral-earnings referrer
                            (+ (default-to u0 (map-get? referral-earnings referrer)) bonus)
                        )
                        
                        ;; Update pool and stats
                        (var-set rewards-pool (- (var-get rewards-pool) bonus))
                        (var-set total-rewards-paid (+ (var-get total-rewards-paid) bonus))
                        
                        (ok bonus)
                    )
                    (ok u0)
                )
            )
            (ok u0) ;; No referrer
        )
    )
)

(define-public (withdraw-earnings)
    (let
        (
            (earnings (get-referral-earnings tx-sender))
        )
        (asserts! (> earnings u0) err-invalid-amount)
        
        ;; Reset earnings
        (map-set referral-earnings tx-sender u0)
        
        (ok earnings)
    )
)

(define-public (owner-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (asserts! (<= amount (var-get rewards-pool)) err-insufficient-balance)
        
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set rewards-pool (- (var-get rewards-pool) amount))
        
        (ok true)
    )
)
