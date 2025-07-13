;; EduFlex - Pay-As-You-Go School Fees System
;; Smart contract for installment-based school fee payments

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_STUDENT_NOT_FOUND (err u201))
(define-constant ERR_SCHOOL_NOT_FOUND (err u202))
(define-constant ERR_INSUFFICIENT_FUNDS (err u203))
(define-constant ERR_INVALID_AMOUNT (err u204))
(define-constant ERR_PHASE_NOT_AVAILABLE (err u205))
(define-constant ERR_PHASE_ALREADY_PAID (err u206))
(define-constant ERR_INVALID_PHASE (err u207))
(define-constant ERR_STUDENT_ALREADY_EXISTS (err u208))
(define-constant ERR_SCHOOL_ALREADY_EXISTS (err u209))
(define-constant ERR_INVALID_STUDENT_ID (err u210))

;; Payment Phases
(define-constant PHASE_REGISTRATION u1)
(define-constant PHASE_TUITION u2)
(define-constant PHASE_EXAMS u3)
(define-constant PHASE_CLEARANCE u4)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var platform-fee-rate uint u50) ;; 0.5% platform fee
(define-data-var next-student-id uint u1)

;; Data Maps
(define-map students
  principal
  {
    student-id: uint,
    school: principal,
    wallet-balance: uint,
    total-fees: uint,
    phases-paid: (list 10 uint),
    current-phase: uint,
    active: bool,
    registration-block: uint
  }
)

(define-map student-by-id
  uint
  principal
)

(define-map schools
  principal
  {
    name: (string-ascii 100),
    active: bool,
    total-students: uint,
    total-collected: uint,
    phase-fees: {
      registration: uint,
      tuition: uint,
      exams: uint,
      clearance: uint
    }
  }
)

(define-map payment-history
  {student: principal, phase: uint}
  {
    amount: uint,
    block-height: uint,
    transaction-id: uint
  }
)

(define-map school-earnings
  {school: principal, phase: uint}
  uint
)

;; Read-only functions
(define-read-only (get-student-info (student principal))
  (map-get? students student)
)

(define-read-only (get-student-by-id (student-id uint))
  (match (map-get? student-by-id student-id)
    student-principal (get-student-info student-principal)
    none
  )
)

(define-read-only (get-school-info (school principal))
  (map-get? schools school)
)

(define-read-only (get-payment-history (student principal) (phase uint))
  (map-get? payment-history {student: student, phase: phase})
)

(define-read-only (get-school-earnings (school principal) (phase uint))
  (default-to u0 (map-get? school-earnings {school: school, phase: phase}))
)

(define-read-only (get-contract-stats)
  {
    active: (var-get contract-active),
    platform-fee-rate: (var-get platform-fee-rate),
    next-student-id: (var-get next-student-id)
  }
)

(define-read-only (get-phase-name (phase uint))
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

(define-read-only (calculate-total-fees (school principal))
  (match (get-school-info school)
    school-info 
    (let ((fees (get phase-fees school-info)))
      (+ (+ (get registration fees) (get tuition fees))
         (+ (get exams fees) (get clearance fees))
      )
    )
    u0
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

(define-private (get-phase-fee (school principal) (phase uint))
  (match (get-school-info school)
    school-info
    (let ((fees (get phase-fees school-info)))
      (if (is-eq phase PHASE_REGISTRATION)
        (get registration fees)
        (if (is-eq phase PHASE_TUITION)
          (get tuition fees)
          (if (is-eq phase PHASE_EXAMS)
            (get exams fees)
            (if (is-eq phase PHASE_CLEARANCE)
              (get clearance fees)
              u0
            )
          )
        )
      )
    )
    u0
  )
)

(define-private (has-paid-phase (phases-paid (list 10 uint)) (phase uint))
  (is-some (index-of phases-paid phase))
)

(define-private (can-pay-phase (student-info {student-id: uint, school: principal, wallet-balance: uint, total-fees: uint, phases-paid: (list 10 uint), current-phase: uint, active: bool, registration-block: uint}) (phase uint))
  (and 
    (get active student-info)
    (is-valid-phase phase)
    (not (has-paid-phase (get phases-paid student-info) phase))
    (or (is-eq phase PHASE_REGISTRATION)
        (has-paid-phase (get phases-paid student-info) (- phase u1))
    )
  )
)

(define-private (calculate-platform-fee (amount uint))
  (/ (* amount (var-get platform-fee-rate)) u10000)
)

;; Public functions

;; Register a new school
(define-public (register-school 
  (name (string-ascii 100))
  (registration-fee uint)
  (tuition-fee uint)
  (exam-fee uint)
  (clearance-fee uint)
)
  (let ((existing-school (get-school-info tx-sender)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-school) ERR_SCHOOL_ALREADY_EXISTS)
    (asserts! (> registration-fee u0) ERR_INVALID_AMOUNT)
    (asserts! (> tuition-fee u0) ERR_INVALID_AMOUNT)
    
    (map-set schools tx-sender {
      name: name,
      active: true,
      total-students: u0,
      total-collected: u0,
      phase-fees: {
        registration: registration-fee,
        tuition: tuition-fee,
        exams: exam-fee,
        clearance: clearance-fee
      }
    })
    
    (ok {
      school: tx-sender,
      name: name,
      total-fees: (+ (+ registration-fee tuition-fee) (+ exam-fee clearance-fee))
    })
  )
)

;; Register a new student
(define-public (register-student (school principal))
  (let (
    (existing-student (get-student-info tx-sender))
    (school-info (unwrap! (get-school-info school) ERR_SCHOOL_NOT_FOUND))
    (student-id (var-get next-student-id))
    (total-fees (calculate-total-fees school))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-student) ERR_STUDENT_ALREADY_EXISTS)
    (asserts! (get active school-info) ERR_SCHOOL_NOT_FOUND)
    
    ;; Create student record
    (map-set students tx-sender {
      student-id: student-id,
      school: school,
      wallet-balance: u0,
      total-fees: total-fees,
      phases-paid: (list),
      current-phase: PHASE_REGISTRATION,
      active: true,
      registration-block: stacks-block-height
    })
    
    ;; Map student ID to principal
    (map-set student-by-id student-id tx-sender)
    
    ;; Update school stats
    (map-set schools school 
      (merge school-info {total-students: (+ (get total-students school-info) u1)})
    )
    
    ;; Increment student ID counter
    (var-set next-student-id (+ student-id u1))
    
    (ok {
      student-id: student-id,
      school: school,
      total-fees: total-fees
    })
  )
)

;; Top up student wallet
(define-public (top-up-wallet (amount uint))
  (let ((student-info (unwrap! (get-student-info tx-sender) ERR_STUDENT_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (get active student-info) ERR_STUDENT_NOT_FOUND)
    
    ;; Transfer STX from student to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update student wallet
    (map-set students tx-sender 
      (merge student-info {
        wallet-balance: (+ (get wallet-balance student-info) amount)
      })
    )
    
    (ok {
      new-balance: (+ (get wallet-balance student-info) amount),
      amount-added: amount
    })
  )
)

;; Pay for a specific phase
(define-public (pay-phase (phase uint))
  (let (
    (student-info (unwrap! (get-student-info tx-sender) ERR_STUDENT_NOT_FOUND))
    (school (get school student-info))
    (phase-fee (get-phase-fee school phase))
    (platform-fee (calculate-platform-fee phase-fee))
    (school-amount (- phase-fee platform-fee))
    (current-earnings (get-school-earnings school phase))
  )
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (can-pay-phase student-info phase) ERR_PHASE_NOT_AVAILABLE)
    (asserts! (>= (get wallet-balance student-info) phase-fee) ERR_INSUFFICIENT_FUNDS)
    
    ;; Update student record
    (map-set students tx-sender 
      (merge student-info {
        wallet-balance: (- (get wallet-balance student-info) phase-fee),
        phases-paid: (unwrap! (as-max-len? (append (get phases-paid student-info) phase) u10) ERR_INVALID_PHASE),
        current-phase: (if (< phase u4) (+ phase u1) phase)
      })
    )
    
    ;; Transfer payment to school
    (try! (as-contract (stx-transfer? school-amount tx-sender school)))
    
    ;; Update school earnings
    (map-set school-earnings {school: school, phase: phase} (+ current-earnings school-amount))
    
    ;; Update school total collected
    (let ((school-info (unwrap! (get-school-info school) ERR_SCHOOL_NOT_FOUND)))
      (map-set schools school 
        (merge school-info {total-collected: (+ (get total-collected school-info) school-amount)})
      )
    )
    
    ;; Record payment history
    (map-set payment-history {student: tx-sender, phase: phase} {
      amount: phase-fee,
      block-height: stacks-block-height,
      transaction-id: u0 ;; Could be enhanced with actual tx ID
    })
    
    (ok {
      phase: phase,
      phase-name: (get-phase-name phase),
      amount-paid: phase-fee,
      platform-fee: platform-fee,
      school-received: school-amount,
      remaining-balance: (- (get wallet-balance student-info) phase-fee),
      next-phase: (if (< phase u4) (+ phase u1) phase)
    })
  )
)

;; Update school fee structure (school only)
(define-public (update-school-fees 
  (registration-fee uint)
  (tuition-fee uint)
  (exam-fee uint)
  (clearance-fee uint)
)
  (let ((school-info (unwrap! (get-school-info tx-sender) ERR_SCHOOL_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    (asserts! (get active school-info) ERR_SCHOOL_NOT_FOUND)
    (asserts! (> registration-fee u0) ERR_INVALID_AMOUNT)
    (asserts! (> tuition-fee u0) ERR_INVALID_AMOUNT)
    
    (map-set schools tx-sender 
      (merge school-info {
        phase-fees: {
          registration: registration-fee,
          tuition: tuition-fee,
          exams: exam-fee,
          clearance: clearance-fee
        }
      })
    )
    
    (ok {
      school: tx-sender,
      new-total-fees: (+ (+ registration-fee tuition-fee) (+ exam-fee clearance-fee))
    })
  )
)

;; Toggle school status (school only)
(define-public (toggle-school-status)
  (let ((school-info (unwrap! (get-school-info tx-sender) ERR_SCHOOL_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_UNAUTHORIZED)
    
    (map-set schools tx-sender 
      (merge school-info {active: (not (get active school-info))})
    )
    
    (ok {school: tx-sender, active: (not (get active school-info))})
  )
)

;; Admin functions (contract owner only)
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (<= new-rate u1000) ERR_INVALID_AMOUNT) ;; Max 10% fee
    (var-set platform-fee-rate new-rate)
    (ok {new-platform-fee-rate: new-rate})
  )
)

(define-public (toggle-contract-status)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-active (not (var-get contract-active)))
    (ok {contract-active: (var-get contract-active)})
  )
)

;; Emergency withdraw (contract owner only)
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok {withdrawn: amount})
  )
)
