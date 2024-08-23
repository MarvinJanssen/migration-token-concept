(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(impl-trait .token-migration-trait.token-migration-trait)

(define-constant err-not-owner (err u100))

(define-constant err-unauthorised (err u101))
(define-constant err-not-contract-owner (err u800))

(define-constant err-not-interim-token (err u1000))
(define-constant err-not-waiting-for-migration (err u1001))
(define-constant err-migration-not-complete (err u1002))
(define-constant err-not-migrating (err u1003))
(define-constant err-already-migrated (err u1004))

(define-constant token-name "USDC")
(define-constant token-symbol "USDC")
(define-constant token-decimals u6)

(define-constant interim-token-principal .interim-usdc)
(define-constant migration-state-waiting 0x00)
(define-constant migration-state-migrating 0x01)
(define-constant migration-state-complete 0x02)

(define-data-var migration-state (buff 1) migration-state-waiting)
(define-data-var migration-snapshot-height uint u0)
(define-data-var migration-snapshot-supply uint u0)
(define-data-var migrated-amount uint u0)
(define-map migrated-amounts principal uint)

(define-data-var contract-owner principal tx-sender)
(define-data-var pending-contract-owner (optional principal) none)

(define-data-var token-uri (optional (string-utf8 256)) none)

(define-fungible-token usdc)

;; sip010

;; Alternatively, we can do a "copy-on-write" and migrate tokens when the user calls transfer for the first
;; time. I do not think it is the right way because it encumbers the transfer function.
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
	(begin
		(asserts! (is-eq migration-state-complete (var-get migration-state)) err-migration-not-complete)
		(asserts! (or (is-eq sender contract-caller) (is-eq sender tx-sender)) err-not-owner)
		(match memo to-print (print to-print) 0x)
		(ft-transfer? usdc amount sender recipient)
	)
)

(define-read-only (get-name)
	(ok token-name)
)

(define-read-only (get-symbol)
	(ok token-symbol)
)

(define-read-only (get-decimals)
	(ok token-decimals)
)

(define-read-only (get-balance (who principal))
	(ok (ft-get-balance usdc who))
)

(define-read-only (get-total-supply)
	(ok (ft-get-supply usdc))
)

(define-read-only (get-token-uri)
	(ok (var-get token-uri))
)

;; mint/burn mechanism

(define-public (mint (amount uint) (recipient principal))
	(begin
		(try! (is-contract-owner))
		(ft-mint? usdc amount recipient)
	)
)

(define-public (burn (amount uint) (victim principal))
	(begin
		(try! (is-contract-owner))
		(ft-burn? usdc amount victim)
	)
)

;; safe ownership

(define-read-only (is-contract-owner)
	(ok (asserts! (is-eq contract-caller (var-get contract-owner)) err-not-contract-owner))
)

(define-public (transfer-contract-ownership (new-owner (optional principal)))
	(begin
		(try! (is-contract-owner))
		(ok (var-set pending-contract-owner new-owner))
	)
)

(define-public (accept-contract-ownership-transfer)
	(begin
		(asserts! (is-eq (some contract-caller) (var-get pending-contract-owner)) err-unauthorised)
		(var-set pending-contract-owner none)
		(ok (var-set contract-owner contract-caller))
	)
)

;; migration

(define-public (start-migration (snapshot-height uint) (total-supply uint))
	(begin
		(asserts! (is-eq interim-token-principal contract-caller) err-not-interim-token)
		(asserts! (is-eq migration-state-waiting (var-get migration-state)) err-not-waiting-for-migration)
		(var-set migration-snapshot-height snapshot-height)
		(var-set migration-state migration-state-migrating)
		(ok (var-set migration-snapshot-supply total-supply))
	)
)

(define-read-only (get-migration-snapshot-supply)
	(var-get migration-snapshot-supply)
)

(define-read-only (get-total-migrated-amount)
	(var-get migrated-amount)
)

(define-read-only (get-migrated-amount (who principal))
	(map-get? migrated-amounts who)
)

;; We can do at-block to be safe, but it should not be necessary if transfer/mint/burn are frozen
;; in the interim contract.
(define-private (migrate-tokens-iter (who principal))
	(let ((snapshot-balance (try! (contract-call? .interim-usdc migrate-balance who))))
		(asserts! (is-none (map-get? migrated-amounts who)) err-already-migrated)
		(map-set migrated-amounts who snapshot-balance)
		(try! (ft-mint? usdc snapshot-balance who))
		(ok snapshot-balance)
	)
)

(define-private (sum-ok (current (response uint uint)) (previous uint))
	(match current
		ok-amount (+ ok-amount previous)
		err previous
	)
)

;; Anyone can call this. People can call it for themselves or benevolent principals can do it for others.
(define-public (migrate-tokens (principals (list 2000 principal)))
	(let (
		(migration-result (map migrate-tokens-iter principals))
		(migration-total (fold sum-ok migration-result u0))
		(total-migrated-amount (+ migration-total (var-get migrated-amount)))
	)
		(asserts! (is-eq migration-state-migrating (var-get migration-state)) err-not-migrating)
		(if (>= total-migrated-amount (var-get migration-snapshot-supply))
			(begin
				(var-set migration-state migration-state-complete)
				(print { event: "migration", complete: true, total: total-migrated-amount })
			)
			(print { event: "migration", complete: false, total: total-migrated-amount })
		)
		(var-set migrated-amount total-migrated-amount)
		(ok migration-result)
	)
)

;; And here we would put any new mechanims in place for the final token, like
;; contract upgradability.
