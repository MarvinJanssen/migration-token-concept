(use-trait sip-010-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-constant err-not-owner (err u100))

(define-constant contract-owner tx-sender)

(define-public (transfer-out (token <sip-010-trait>) (amount uint) (recipient principal))
	(begin
		(asserts! (is-eq contract-owner contract-caller) err-not-owner)
		(as-contract (contract-call? token transfer amount contract-caller recipient none))
	)
)
