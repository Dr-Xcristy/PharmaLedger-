;; PharmaLedger Contract
;;
;; This contract provides a transparent and immutable ledger for tracking
;; pharmaceutical drug batches through the supply chain.
;;
;; Features:
;; - Registration of trusted manufacturers and distributors by a contract administrator.
;; - Creation of unique drug types with metadata.
;; - Minting of specific drug batches, linked to a drug type.
;; - A secure custody transfer mechanism for each batch.
;; - Publicly verifiable history for every batch.
;;
;; Version: 1.0.1
;; Author: [Your Name]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants and Error Codes ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant CONTRACT-ADMIN tx-sender)

;; Error Codes
(define-constant ERR-UNAUTHORIZED u101)
(define-constant ERR-MANUFACTURER-NOT-FOUND u102)
(define-constant ERR-DISTRIBUTOR-NOT-FOUND u103)
(define-constant ERR-DRUG-TYPE-NOT-FOUND u104)
(define-constant ERR-BATCH-NOT-FOUND u105)
(define-constant ERR-NOT-BATCH-OWNER u106)
(define-constant ERR-INVALID-CUSTODIAN u107)
(define-constant ERR-ALREADY-REGISTERED u108)
(define-constant ERR-EMPTY-METADATA u109)
(define-constant ERR-CUSTODY-HISTORY-FULL u110)

;;;;;;;;;;;;;;;;;;;;;;;
;; Data Structures ;;
;;;;;;;;;;;;;;;;;;;;;;;

;; -- State Variables --
(define-data-var last-drug-id uint u0)
(define-data-var last-batch-id uint u0)

;; -- Maps --

;; Stores trusted manufacturer principals
(define-map manufacturers principal bool)

;; Stores trusted distributor principals
(define-map distributors principal bool)

;; Stores information about each type of drug
;; Key: uint (drug-id)
;; Value: { name: (buff 32), formula: (buff 64), manufacturer: principal }
(define-map drug-types uint
  {
    name: (buff 32),
    formula: (buff 64),
    manufacturer: principal
  }
)

;; Stores information about each specific batch of a drug
;; Key: uint (batch-id)
;; Value: { drug-id: uint, mfg-date: uint, exp-date: uint, current-owner: principal, metadata-uri: (string-ascii 256) }
(define-map drug-batches uint
  {
    drug-id: uint,
    mfg-date: uint,
    exp-date: uint,
    current-owner: principal,
    metadata-uri: (string-ascii 256)
  }
)

;; Stores the custody history for each batch
;; Key: uint (batch-id)
;; Value: A list of principals who have held the batch
(define-map batch-custody-history uint (list 200 principal))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Administrative Functions  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Adds a new trusted manufacturer to the system.
;; @param new-manufacturer: The principal of the manufacturer to add.
;; @returns (response bool uint)
(define-public (add-manufacturer (new-manufacturer principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-ADMIN) (err ERR-UNAUTHORIZED))
    (asserts! (is-none (map-get? manufacturers new-manufacturer)) (err ERR-ALREADY-REGISTERED))
    (map-set manufacturers new-manufacturer true)
    (ok true)
  )
)

;; @desc Adds a new trusted distributor to the system.
;; @param new-distributor: The principal of the distributor to add.
;; @returns (response bool uint)
(define-public (add-distributor (new-distributor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-ADMIN) (err ERR-UNAUTHORIZED))
    (asserts! (is-none (map-get? distributors new-distributor)) (err ERR-ALREADY-REGISTERED))
    (map-set distributors new-distributor true)
    (ok true)
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Core Logic - Manufacturers ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Allows a registered manufacturer to define a new type of drug.
;; @param name: The brand name of the drug.
;; @param formula: The chemical formula or active ingredient.
;; @returns (response uint uint) - The new drug-id.
(define-public (register-drug-type (name (buff 32)) (formula (buff 64)))
  (begin
    (asserts! (is-some (map-get? manufacturers tx-sender)) (err ERR-MANUFACTURER-NOT-FOUND))
    (let ((drug-id (+ u1 (var-get last-drug-id))))
      (map-set drug-types drug-id
        {
          name: name,
          formula: formula,
          manufacturer: tx-sender
        }
      )
      (var-set last-drug-id drug-id)
      (print { action: "register-drug-type", drug-id: drug-id, manufacturer: tx-sender })
      (ok drug-id)
    )
  )
)

;; @desc Allows the original manufacturer to mint a new batch of a registered drug.
;; @param drug-id: The ID of the drug type to mint a batch for.
;; @param mfg-date: The manufacturing date (e.g., Unix timestamp).
;; @param exp-date: The expiration date (e.g., Unix timestamp).
;; @param metadata-uri: A link to off-chain batch-specific data (e.g., lab results).
;; @returns (response uint uint) - The new batch-id.
(define-public (create-drug-batch (drug-id uint) (mfg-date uint) (exp-date uint) (metadata-uri (string-ascii 256)))
  (begin
    (let
      (
        (drug-info (unwrap! (map-get? drug-types drug-id) (err ERR-DRUG-TYPE-NOT-FOUND)))
      )
      ;; Ensure the caller is the original manufacturer of this drug type
      (asserts! (is-eq tx-sender (get manufacturer drug-info)) (err ERR-UNAUTHORIZED))
      (let ((batch-id (+ u1 (var-get last-batch-id))))
        ;; Create the batch record
        (map-set drug-batches batch-id
          {
            drug-id: drug-id,
            mfg-date: mfg-date,
            exp-date: exp-date,
            current-owner: tx-sender,
            metadata-uri: metadata-uri
          }
        )
        ;; Initialize the custody history with the manufacturer
        (map-set batch-custody-history batch-id (list tx-sender))
        (var-set last-batch-id batch-id)
        (print { action: "create-drug-batch", batch-id: batch-id, drug-id: drug-id })
        (ok batch-id)
      )
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Core Logic - Custody     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Transfers ownership of a drug batch to a new custodian (e.g., a distributor).
;; @param batch-id: The ID of the batch to transfer.
;; @param new-custodian: The principal of the new owner.
;; @returns (response bool uint)
(define-public (transfer-batch-custody (batch-id uint) (new-custodian principal))
  (begin
    ;; Ensure the new custodian is a registered manufacturer or distributor
    (asserts! (or (is-some (map-get? manufacturers new-custodian)) (is-some (map-get? distributors new-custodian))) (err ERR-INVALID-CUSTODIAN))
    (let
      (
        (batch-record (unwrap! (map-get? drug-batches batch-id) (err ERR-BATCH-NOT-FOUND)))
        (current-owner (get current-owner batch-record))
        (custody-history (unwrap! (map-get? batch-custody-history batch-id) (err ERR-BATCH-NOT-FOUND)))
      )
      ;; Ensure the caller is the current owner of the batch
      (asserts! (is-eq tx-sender current-owner) (err ERR-NOT-BATCH-OWNER))
      ;; Check if we can add another entry to the custody history
      (asserts! (< (len custody-history) u200) (err ERR-CUSTODY-HISTORY-FULL))
      ;; Update the batch owner
      (map-set drug-batches batch-id (merge batch-record { current-owner: new-custodian }))
      ;; Append the new owner to the custody history
      (map-set batch-custody-history batch-id (unwrap! (as-max-len? (append custody-history new-custodian) u200) (err ERR-CUSTODY-HISTORY-FULL)))
      (print { action: "transfer-custody", batch-id: batch-id, from: tx-sender, to: new-custodian })
      (ok true)
    )
  )
)

;;;;;;;;;;;;;;;;;;;;;;;;;
;; Read-Only Functions ;;
;;;;;;;;;;;;;;;;;;;;;;;;;

;; @desc Gets the details of a specific drug type.
;; @param drug-id: The ID of the drug type.
;; @returns (optional { name: (buff 32), formula: (buff 64), manufacturer: principal })
(define-read-only (get-drug-type-info (drug-id uint))
  (map-get? drug-types drug-id)
)

;; @desc Gets the details of a specific drug batch.
;; @param batch-id: The ID of the batch.
;; @returns (optional { drug-id: uint, mfg-date: uint, exp-date: uint, current-owner: principal, metadata-uri: (string-ascii 256) })
(define-read-only (get-batch-info (batch-id uint))
  (map-get? drug-batches batch-id)
)

;; @desc Gets the complete custody history of a specific drug batch.
;; @param batch-id: The ID of the batch.
;; @returns (optional (list 200 principal))
(define-read-only (get-batch-custody-history (batch-id uint))
  (map-get? batch-custody-history batch-id)
)

;; @desc Checks if a principal is a registered manufacturer.
;; @param who: The principal to check.
;; @returns bool
(define-read-only (is-manufacturer (who principal))
  (is-some (map-get? manufacturers who))
)

;; @desc Checks if a principal is a registered distributor.
;; @param who: The principal to check.
;; @returns bool
(define-read-only (is-distributor (who principal))
  (is-some (map-get? distributors who))
)

;; @desc Gets the total number of drug types registered.
;; @returns uint
(define-read-only (get-total-drug-types)
  (var-get last-drug-id)
)

;; @desc Gets the total number of batches created.
;; @returns uint
(define-read-only (get-total-batches)
  (var-get last-batch-id)
)