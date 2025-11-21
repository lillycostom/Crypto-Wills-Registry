(define-non-fungible-token will-nft uint)

(define-constant contract-owner tx-sender)
(define-constant err-not-authorized (err u100))
(define-constant err-will-exists (err u101))
(define-constant err-no-will-found (err u102))
(define-constant err-invalid-witness (err u103))
(define-constant err-not-enough-witnesses (err u104))
(define-constant err-already-witnessed (err u105))
(define-constant err-not-active (err u106))
(define-constant err-already-executed (err u107))
(define-constant err-recovery-not-authorized (err u108))
(define-constant err-recovery-too-early (err u109))
(define-constant err-cannot-update-executed (err u110))
(define-constant minimum-witnesses u2)
(define-constant recovery-delay-blocks u1440)

(define-map wills
    uint
    {
        testator: principal,
        ipfs-hash: (string-ascii 64),
        witnesses: (list 5 principal),
        required-witnesses: uint,
        execution-height: uint,
        is-active: bool,
        is-executed: bool,
        beneficiary: principal,
        recovery-contact: (optional principal),
        recovery-initiated-at: (optional uint),
    }
)

(define-map witness-signatures
    {
        will-id: uint,
        witness: principal,
    }
    { has-signed: bool }
)

(define-data-var will-nonce uint u0)

(define-read-only (get-will (will-id uint))
    (map-get? wills will-id)
)

(define-read-only (get-witness-status
        (will-id uint)
        (witness principal)
    )
    (default-to { has-signed: false }
        (map-get? witness-signatures {
            will-id: will-id,
            witness: witness,
        })
    )
)

(define-read-only (is-valid-witness
        (will-id uint)
        (witness principal)
    )
    (let ((current-will (unwrap! (get-will will-id) false)))
        (is-some (index-of (get witnesses current-will) witness))
    )
)

(define-read-only (count-witness-signatures (will-id uint))
    (let ((current-will (unwrap! (get-will will-id) u0)))
        (get count
            (fold count-signatures-helper (get witnesses current-will) {
                will-id: will-id,
                count: u0,
            })
        )
    )
)

(define-read-only (get-will-overview (will-id uint))
    (let (
            (current-will (unwrap! (get-will will-id) err-no-will-found))
            (signatures (count-witness-signatures will-id))
            (can-execute (and
                (get is-active current-will)
                (not (get is-executed current-will))
                (>= signatures (get required-witnesses current-will))
                (>= stacks-block-height (get execution-height current-will))
            ))
            (has-recovery-contact (is-some (get recovery-contact current-will)))
            (is-recovery-initiated (is-some (get recovery-initiated-at current-will)))
        )
        (ok {
            will-id: will-id,
            testator: (get testator current-will),
            beneficiary: (get beneficiary current-will),
            ipfs-hash: (get ipfs-hash current-will),
            required-witnesses: (get required-witnesses current-will),
            witness-signatures: signatures,
            execution-height: (get execution-height current-will),
            is-active: (get is-active current-will),
            is-executed: (get is-executed current-will),
            can-execute: can-execute,
            has-recovery-contact: has-recovery-contact,
            is-recovery-initiated: is-recovery-initiated,
        })
    )
)

(define-private (count-signatures-helper
        (witness principal)
        (acc {
            will-id: uint,
            count: uint,
        })
    )
    (let ((status (get-witness-status (get will-id acc) witness)))
        {
            will-id: (get will-id acc),
            count: (if (get has-signed status)
                (+ (get count acc) u1)
                (get count acc)
            ),
        }
    )
)

(define-public (register-will
        (ipfs-hash (string-ascii 64))
        (witnesses (list 5 principal))
        (required-witnesses uint)
        (execution-height uint)
        (beneficiary principal)
        (recovery-contact (optional principal))
    )
    (let ((will-id (var-get will-nonce)))
        (asserts! (>= required-witnesses minimum-witnesses)
            err-not-enough-witnesses
        )
        (asserts! (<= required-witnesses (len witnesses))
            err-not-enough-witnesses
        )
        (try! (nft-mint? will-nft will-id tx-sender))
        (map-set wills will-id {
            testator: tx-sender,
            ipfs-hash: ipfs-hash,
            witnesses: witnesses,
            required-witnesses: required-witnesses,
            execution-height: execution-height,
            is-active: true,
            is-executed: false,
            beneficiary: beneficiary,
            recovery-contact: recovery-contact,
            recovery-initiated-at: none,
        })
        (var-set will-nonce (+ will-id u1))
        (ok will-id)
    )
)

(define-public (witness-sign (will-id uint))
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-valid-witness will-id tx-sender) err-invalid-witness)
        (asserts! (get is-active current-will) err-not-active)
        (asserts! (not (get is-executed current-will)) err-already-executed)
        (asserts! (not (get has-signed (get-witness-status will-id tx-sender)))
            err-already-witnessed
        )
        (map-set witness-signatures {
            will-id: will-id,
            witness: tx-sender,
        } { has-signed: true }
        )
        (ok true)
    )
)

(define-public (execute-will (will-id uint))
    (let (
            (current-will (unwrap! (get-will will-id) err-no-will-found))
            (signatures (count-witness-signatures will-id))
        )
        (asserts! (get is-active current-will) err-not-active)
        (asserts! (not (get is-executed current-will)) err-already-executed)
        (asserts! (>= signatures (get required-witnesses current-will))
            err-not-enough-witnesses
        )
        (asserts! (>= stacks-block-height (get execution-height current-will))
            err-not-active
        )
        (try! (nft-transfer? will-nft will-id (get testator current-will)
            (get beneficiary current-will)
        ))
        (map-set wills will-id (merge current-will { is-executed: true }))
        (ok true)
    )
)

(define-public (revoke-will (will-id uint))
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-eq tx-sender (get testator current-will))
            err-not-authorized
        )
        (asserts! (not (get is-executed current-will)) err-already-executed)
        (map-set wills will-id (merge current-will { is-active: false }))
        (ok true)
    )
)

(define-public (initiate-recovery (will-id uint))
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-some (get recovery-contact current-will))
            err-recovery-not-authorized
        )
        (asserts!
            (is-eq tx-sender (unwrap-panic (get recovery-contact current-will)))
            err-recovery-not-authorized
        )
        (asserts! (get is-active current-will) err-not-active)
        (asserts! (not (get is-executed current-will)) err-already-executed)
        (asserts! (is-none (get recovery-initiated-at current-will))
            err-recovery-not-authorized
        )
        (map-set wills will-id
            (merge current-will { recovery-initiated-at: (some stacks-block-height) })
        )
        (ok true)
    )
)

(define-public (complete-recovery
        (will-id uint)
        (new-testator principal)
    )
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-some (get recovery-contact current-will))
            err-recovery-not-authorized
        )
        (asserts!
            (is-eq tx-sender (unwrap-panic (get recovery-contact current-will)))
            err-recovery-not-authorized
        )
        (asserts! (get is-active current-will) err-not-active)
        (asserts! (not (get is-executed current-will)) err-already-executed)
        (asserts! (is-some (get recovery-initiated-at current-will))
            err-recovery-too-early
        )
        (asserts!
            (>= stacks-block-height
                (+ (unwrap-panic (get recovery-initiated-at current-will))
                    recovery-delay-blocks
                ))
            err-recovery-too-early
        )
        (try! (nft-transfer? will-nft will-id (get testator current-will) new-testator))
        (map-set wills will-id
            (merge current-will {
                testator: new-testator,
                recovery-initiated-at: none,
            })
        )
        (ok true)
    )
)

(define-public (update-will
        (will-id uint)
        (new-ipfs-hash (optional (string-ascii 64)))
        (new-beneficiary (optional principal))
        (new-execution-height (optional uint))
        (new-recovery-contact (optional (optional principal)))
    )
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-eq tx-sender (get testator current-will))
            err-not-authorized
        )
        (asserts! (get is-active current-will) err-not-active)
        (asserts! (not (get is-executed current-will)) err-cannot-update-executed)
        (asserts! (is-none (get recovery-initiated-at current-will))
            err-recovery-not-authorized
        )
        (let ((updated-will (merge current-will {
                ipfs-hash: (default-to (get ipfs-hash current-will) new-ipfs-hash),
                beneficiary: (default-to (get beneficiary current-will) new-beneficiary),
                execution-height: (default-to (get execution-height current-will)
                    new-execution-height
                ),
                recovery-contact: (default-to (get recovery-contact current-will)
                    new-recovery-contact
                ),
            })))
            (map-set wills will-id updated-will)
            (ok true)
        )
    )
)

(define-public (cancel-recovery (will-id uint))
    (let ((current-will (unwrap! (get-will will-id) err-no-will-found)))
        (asserts! (is-eq tx-sender (get testator current-will))
            err-not-authorized
        )
        (asserts! (is-some (get recovery-initiated-at current-will))
            err-recovery-not-authorized
        )
        (map-set wills will-id
            (merge current-will { recovery-initiated-at: none })
        )
        (ok true)
    )
)
