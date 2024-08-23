(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)
(impl-trait .interim-token-trait.interim-token-trait)
(use-trait token-migration-trait .token-migration-trait.token-migration-trait)

(define-constant err-not-owner (err u100))
(define-constant err-unauthorised (err u101))
(define-constant err-not-migration-manager (err u102))
(define-constant err-not-contract-owner (err u800))
(define-constant err-deprecated (err u900))

(define-constant token-name "USDC")
(define-constant token-symbol "USDC")
(define-constant token-decimals u6)

(define-constant migration-wait-period u6)

(define-data-var token-uri (optional (string-utf8 256)) none)
(define-data-var contract-owner principal tx-sender)
(define-data-var pending-contract-owner (optional principal) none)

(define-data-var migration-start-height uint u0)
(define-data-var migration-manager (optional principal) none)

(define-fungible-token usdc)

;; sip010

(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
	(begin
		(try! (is-not-migrated))
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

;; safe ownership

(define-read-only (is-contract-owner)
	(ok (asserts! (is-eq contract-caller (var-get contract-owner)) err-not-contract-owner))
)

(define-public (transfer-contract-ownership (new-owner (optional principal)))
	(begin
		(try! (is-not-migrated))
		(try! (is-contract-owner))
		(ok (var-set pending-contract-owner new-owner))
	)
)

(define-public (accept-contract-ownership-transfer)
	(begin
		(try! (is-not-migrated))
		(asserts! (is-eq (some contract-caller) (var-get pending-contract-owner)) err-unauthorised)
		(var-set pending-contract-owner none)
		(ok (var-set contract-owner contract-caller))
	)
)

;; mint/burn mechanism

(define-public (mint (amount uint) (recipient principal))
	(begin
		(try! (is-not-migrated))
		(try! (is-contract-owner))
		(ft-mint? usdc amount recipient)
	)
)

(define-public (burn (amount uint) (victim principal))
	(begin
		(try! (is-not-migrated))
		(try! (is-contract-owner))
		(ft-burn? usdc amount victim)
	)
)

;; migration

(define-read-only (is-not-migrated)
	(ok (asserts! (is-eq u0 (var-get migration-start-height)) err-deprecated))
)

(define-public (start-migration (new-token-uri (optional (string-utf8 256))) (manager <token-migration-trait>))
	(begin
		(try! (is-not-migrated))
		(try! (is-contract-owner))
		(var-set migration-start-height burn-block-height)
		(var-set token-uri new-token-uri)
		;; We could additionally set the name to "USDC (deprecated)" or something similar.
		(var-set migration-manager (some (contract-of manager)))
		(contract-call? manager start-migration burn-block-height (ft-get-supply usdc))
	)
)

(define-public (migrate-balance (who principal))
	(let ((balance (ft-get-balance usdc who)))
		(asserts! (is-eq (var-get migration-manager) (some contract-caller)) err-not-migration-manager)
		(asserts! (> balance u0) (ok u0))
		(try! (ft-burn? usdc balance who))
		(ok balance)
	)
)
