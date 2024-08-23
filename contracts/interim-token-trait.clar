(use-trait token-migration-trait .token-migration-trait.token-migration-trait)

(define-trait interim-token-trait
	(
		(start-migration ((optional (string-utf8 256)) <token-migration-trait>) (response bool uint))
		(migrate-balance (principal) (response uint uint))
		;;(migrate-balance-many ((list 2000 principal)) (response (list 2000 uint) uint))
	)
)
