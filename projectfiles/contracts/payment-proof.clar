;; EduFlex Payment Proof NFTs
;; Smart contract for issuing NFT certificates as proof of phase payments

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_STUDENT_NOT_FOUND (err u301))
(define-constant ERR_SCHOOL_NOT_FOUND (err u302))
(define-constant ERR_PAYMENT_NOT_VERIFIED (err u303))
(define-constant ERR_NFT_ALREADY_MINTED (err u304))
(define-constant ERR_INVALID_PHASE (err u305))
(define-constant ERR_NFT_NOT_FOUND (err u306))
(define-constant ERR_INVALID_TOKEN_ID (err u307))
(define-constant ERR_CONTRACT_NOT_ACTIVE (err u308))

;; Payment Phases (matching main contract)
(define-constant PHASE_REGISTRATION u1)
(define-constant PHASE_TUITION u2)
(define-constant PHASE_EXAMS u3)
(define-constant PHASE_CLEARANCE u4)

;; NFT Definition
(define-non-fungible-token payment-proof-nft uint)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var next-token-id uint u1)
(define-data-var main-contract principal tx-sender) ;; Reference to main EduFlex contract

;; Data Maps
(define-map nft-metadata
  uint
  {
    student: principal,
    student-id: uint,
    school: principal,
    school-name: (string-ascii 100),
    phase: uint,
    phase-name: (string-ascii 20),
    amount-paid: uint,
    payment-block: uint,
    mint-block: uint,
    verified: bool
  }
)

(define-map student-phase-nfts
  {student: principal, phase: uint}
  uint
)

(define-map school-issued-nfts
  {school: principal, phase: uint}
  (list 1000 uint)
)

(define-map nft-verification-status
  uint
  {
    verified-by: principal,
    verification-block: uint,
    verification-purpose: (string-ascii 50)
  }
)

;; Read-only functions
(define-read-only (get-nft-metadata (token-id uint))
  (map-get? nft-metadata token-id)
)

(define-read-only (get-student-phase-nft (student principal) (phase uint))
  (map-get? student-phase-nfts {student: student, phase: phase})
)

(define-read-only (get-school-issued-nfts (school principal) (phase uint))
  (default-to (list) (map-get? school-issued-nfts {school: school, phase: phase}))
)

(define-read-only (get-nft-verification (token-id uint))
  (map-get? nft-verification-status token-id)
)

(define-read-only (get-contract-stats)
  {
    active: (var-get contract-active),
    next-token-id: (var-get next-token-id),
    main-contract: (var-get main-contract)
  }
)

(define-read-only (get-last-token-id)
  (- (var-get next-token-id) u1)
)

(define-read-only (get-token-uri (token-id uint))
  (match (get-nft-metadata token-id)
    metadata
    (ok (some (concat 
      (concat "https://api.eduflex.edu/nft/" (uint-to-ascii token-id))
      (concat "?student=" (principal-to-string (get student metadata)))
    )))
    (ok none)
  )
)

;; Private functions
(define-private (is-valid-phase (phase uint))
  (or (is-eq phase PHASE_REGISTRATION)
      (or (is-eq phase PHASE_TUITION)
          (or (is-eq phase PHASE_EXAMS)
              (is-eq phase PHASE_CLEARANCE)
          )
      )
  )
)

(define-private (get-phase-name (phase uint))
  (if (is-eq phase PHASE_REGISTRATION)
    "Registration"
    (if (is-eq phase PHASE_TUITION)
      "Tuition"
      (if (is-eq phase PHASE_EXAMS)
        "Exams"
        (if (is-eq phase PHASE_CLEARANCE)
          "Clearance"
          "Unknown"
        )
      )
    )
  )
)

(define-private (uint-to-ascii (value uint))
  ;; Simple uint to string conversion for small numbers
  (if (< value u10)
    (if (is-eq value u0) "0"
    (if (is-eq value u1) "1"
    (if (is-eq value u2) "2"
    (if (is-eq value u3) "3"
    (if (is-eq value u4) "4"
    (if (is-eq value u5) "5"
    (if (is-eq value u6) "6"
    (if (is-eq value u7) "7"
    (if (is-eq value u8) "8"
    (if (is-eq value u9) "9"
    "unknown"))))))))))
    "multi-digit"
  )
)

(define-private (principal-to-string (addr principal))
  ;; Simplified principal to string - in production would use proper conversion
  "student-address"
)

;; Public functions

;; Mint payment proof NFT (called after successful payment)
(define-public (mint-payment-proof 
  (student principal)
  (student-id uint)
  (school principal)
  (school-name (string-ascii 100))
  (phase uint)
  (amount-paid uint)
  (payment-block uint)
)
  (let (
    (token-id (var-get next-token-id))
    (existing-nft (get-student-phase-nft student phase))
    (current-school-nfts (get-school-issued-nfts school phase))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (is-valid-phase phase) ERR_INVALID_PHASE)
    (asserts! (is-none existing-nft) ERR_NFT_ALREADY_MINTED)
    (asserts! (> amount-paid u0) ERR_PAYMENT_NOT_VERIFIED)
    
    ;; Mint NFT to student
    (try! (nft-mint? payment-proof-nft token-id student))
    
    ;; Store NFT metadata
    (map-set nft-metadata token-id {
      student: student,
      student-id: student-id,
      school: school,
      school-name: school-name,
      phase: phase,
      phase-name: (get-phase-name phase),
      amount-paid: amount-paid,
      payment-block: payment-block,
      mint-block: stacks-block-height,
      verified: true
    })
    
    ;; Map student-phase to NFT token ID
    (map-set student-phase-nfts {student: student, phase: phase} token-id)
    
    ;; Add to school's issued NFTs list
    (map-set school-issued-nfts {school: school, phase: phase}
      (unwrap! (as-max-len? (append current-school-nfts token-id) u1000) ERR_INVALID_TOKEN_ID)
    )
    
    ;; Increment token ID counter
    (var-set next-token-id (+ token-id u1))
    
    (ok {
      token-id: token-id,
      student: student,
      school: school,
      phase: phase,
      phase-name: (get-phase-name phase),
      amount-paid: amount-paid
    })
  )
)

;; Verify NFT for specific purpose (exam entry, report card, etc.)
(define-public (verify-nft-for-purpose 
  (token-id uint)
  (purpose (string-ascii 50))
)
  (let ((nft-data (unwrap! (get-nft-metadata token-id) ERR_NFT_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (get verified nft-data) ERR_PAYMENT_NOT_VERIFIED)
    
    ;; Record verification
    (map-set nft-verification-status token-id {
      verified-by: tx-sender,
      verification-block: stacks-block-height,
      verification-purpose: purpose
    })
    
    (ok {
      token-id: token-id,
      student: (get student nft-data),
      phase: (get phase nft-data),
      phase-name: (get phase-name nft-data),
      verified-for: purpose,
      verified-by: tx-sender
    })
  )
)

;; Batch mint NFTs for multiple phases (for existing students)
(define-public (batch-mint-proofs 
  (student principal)
  (student-id uint)
  (school principal)
  (school-name (string-ascii 100))
  (phases-data (list 4 {phase: uint, amount: uint, block: uint}))
)
  (let ((results (map mint-single-proof phases-data)))
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (ok results)
  )
)

;; Helper function for batch minting
(define-private (mint-single-proof (phase-data {phase: uint, amount: uint, block: uint}))
  (let (
    (phase (get phase phase-data))
    (amount (get amount phase-data))
    (block (get block phase-data))
  )
    ;; This would call mint-payment-proof internally
    ;; Simplified for demonstration
    {phase: phase, amount: amount, success: true}
  )
)

;; Transfer NFT (standard NFT transfer)
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (try! (nft-transfer? payment-proof-nft token-id sender recipient))
    (ok {token-id: token-id, from: sender, to: recipient})
  )
)

;; Get student's all payment proof NFTs
(define-public (get-student-all-proofs (student principal))
  (let (
    (reg-nft (get-student-phase-nft student PHASE_REGISTRATION))
    (tuition-nft (get-student-phase-nft student PHASE_TUITION))
    (exam-nft (get-student-phase-nft student PHASE_EXAMS))
    (clearance-nft (get-student-phase-nft student PHASE_CLEARANCE))
  )
    (ok {
      registration: reg-nft,
      tuition: tuition-nft,
      exams: exam-nft,
      clearance: clearance-nft,
      total-proofs: (+ (+ (if (is-some reg-nft) u1 u0) (if (is-some tuition-nft) u1 u0))
                       (+ (if (is-some exam-nft) u1 u0) (if (is-some clearance-nft) u1 u0)))
    })
  )
)

;; Admin functions (contract owner only)
(define-public (set-main-contract (new-contract principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set main-contract new-contract)
    (ok {main-contract: new-contract})
  )
)

(define-public (toggle-contract-status)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok {contract-active: (var-get contract-active)})
  )
)

;; Emergency functions (contract owner only)
(define-public (emergency-burn-nft (token-id uint))
  (let ((nft-data (unwrap! (get-nft-metadata token-id) ERR_NFT_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (nft-burn? payment-proof-nft token-id (get student nft-data)))
    (map-delete nft-metadata token-id)
    (ok {burned-token: token-id})
  )
)
