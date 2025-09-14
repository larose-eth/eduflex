;; EduFlex Penalty + Reward Layer
;; Smart contract for time-based payment incentives and penalties

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_STUDENT_NOT_FOUND (err u401))
(define-constant ERR_SCHOOL_NOT_FOUND (err u402))
(define-constant ERR_INVALID_PHASE (err u403))
(define-constant ERR_PAYMENT_NOT_DUE (err u404))
(define-constant ERR_REWARD_ALREADY_CLAIMED (err u405))
(define-constant ERR_PENALTY_ALREADY_APPLIED (err u406))
(define-constant ERR_INVALID_DEADLINE (err u407))
(define-constant ERR_CONTRACT_NOT_ACTIVE (err u408))

;; Payment Phases
(define-constant PHASE_REGISTRATION u1)
(define-constant PHASE_TUITION u2)
(define-constant PHASE_EXAMS u3)
(define-constant PHASE_CLEARANCE u4)

;; Reward/Penalty Constants
(define-constant EARLY_PAYMENT_REWARD_RATE u200) ;; 2% discount for early payment
(define-constant LATE_PAYMENT_PENALTY_RATE u150) ;; 1.5% penalty for late payment
(define-constant EARLY_PAYMENT_WINDOW u144) ;; 1 day in blocks (144 blocks-24 hours)
(define-constant GRACE_PERIOD u288) ;; 2 days grace period before penalties

;; NFT Definition for Reward Badges
(define-non-fungible-token early-payment-badge uint)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var next-badge-id uint u1)
(define-data-var main-contract principal tx-sender)

;; Data Maps
(define-map payment-deadlines
  {student: principal, phase: uint}
  {
    due-block: uint,
    early-deadline: uint,
    grace-deadline: uint,
    set-by: principal,
    set-block: uint
  }
)

(define-map penalty-records
  {student: principal, phase: uint}
  {
    penalty-amount: uint,
    applied-block: uint,
    days-late: uint,
    paid: bool
  }
)

(define-map reward-records
  {student: principal, phase: uint}
  {
    reward-amount: uint,
    reward-type: (string-ascii 20),
    claimed-block: uint,
    badge-token-id: (optional uint)
  }
)

(define-map student-reward-stats
  principal
  {
    total-rewards-earned: uint,
    total-penalties-paid: uint,
    early-payments: uint,
    late-payments: uint,
    badge-count: uint
  }
)

(define-map badge-metadata
  uint
  {
    student: principal,
    phase: uint,
    reward-amount: uint,
    earned-block: uint,
    badge-type: (string-ascii 30)
  }
)

;; Read-only functions
(define-read-only (get-payment-deadline (student principal) (phase uint))
  (map-get? payment-deadlines {student: student, phase: phase})
)

(define-read-only (get-penalty-record (student principal) (phase uint))
  (map-get? penalty-records {student: student, phase: phase})
)

(define-read-only (get-reward-record (student principal) (phase uint))
  (map-get? reward-records {student: student, phase: phase})
)

(define-read-only (get-student-stats (student principal))
  (default-to 
    {total-rewards-earned: u0, total-penalties-paid: u0, early-payments: u0, late-payments: u0, badge-count: u0}
    (map-get? student-reward-stats student)
  )
)

(define-read-only (get-badge-metadata (badge-id uint))
  (map-get? badge-metadata badge-id)
)

(define-read-only (calculate-early-reward (base-amount uint))
  (/ (* base-amount EARLY_PAYMENT_REWARD_RATE) u10000)
)

(define-read-only (calculate-late-penalty (base-amount uint) (days-late uint))
  (let ((penalty-multiplier (if (> days-late u7) u2 u1))) ;; Double penalty after 1 week
    (/ (* (* base-amount LATE_PAYMENT_PENALTY_RATE) penalty-multiplier) u10000)
  )
)

(define-read-only (get-payment-status (student principal) (phase uint))
  (let (
    (deadline-info (get-payment-deadline student phase))
    (current-block stacks-block-height)
  )
    (match deadline-info
      deadline-data
      (let (
        (due-block (get due-block deadline-data))
        (early-deadline (get early-deadline deadline-data))
        (grace-deadline (get grace-deadline deadline-data))
      )
        {
          status: (if (< current-block early-deadline)
                   "early-window"
                   (if (< current-block due-block)
                     "on-time"
                     (if (< current-block grace-deadline)
                       "grace-period"
                       "overdue"
                     )
                   )
                 ),
          blocks-until-due: (if (> due-block current-block) (- due-block current-block) u0),
          blocks-overdue: (if (> current-block grace-deadline) (- current-block grace-deadline) u0)
        }
      )
      {status: "no-deadline", blocks-until-due: u0, blocks-overdue: u0}
    )
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

(define-private (calculate-days-late (grace-deadline uint) (current-block uint))
  (if (> current-block grace-deadline)
    (/ (- current-block grace-deadline) u144) ;; Convert blocks to days
    u0
  )
)

;; Public functions

;; Set payment deadline for a student phase (called by school)
(define-public (set-payment-deadline 
  (student principal)
  (phase uint)
  (due-block uint)
)
  (let (
    (early-deadline (- due-block EARLY_PAYMENT_WINDOW))
    (grace-deadline (+ due-block GRACE_PERIOD))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (is-valid-phase phase) ERR_INVALID_PHASE)
    (asserts! (> due-block stacks-block-height) ERR_INVALID_DEADLINE)
    
    (map-set payment-deadlines {student: student, phase: phase} {
      due-block: due-block,
      early-deadline: early-deadline,
      grace-deadline: grace-deadline,
      set-by: tx-sender,
      set-block: stacks-block-height
    })
    
    (ok {
      student: student,
      phase: phase,
      due-block: due-block,
      early-deadline: early-deadline,
      grace-deadline: grace-deadline
    })
  )
)

;; Process early payment reward
(define-public (process-early-payment-reward
  (student principal)
  (phase uint)
  (payment-amount uint)
)
  (let (
    (deadline-info (unwrap! (get-payment-deadline student phase) ERR_PAYMENT_NOT_DUE))
    (current-block stacks-block-height)
    (early-deadline (get early-deadline deadline-info))
    (reward-amount (calculate-early-reward payment-amount))
    (badge-id (var-get next-badge-id))
    (current-stats (get-student-stats student))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (< current-block early-deadline) ERR_PAYMENT_NOT_DUE)
    (asserts! (is-none (get-reward-record student phase)) ERR_REWARD_ALREADY_CLAIMED)
    
    ;; Mint early payment badge NFT
    (try! (nft-mint? early-payment-badge badge-id student))
    
    ;; Record reward
    (map-set reward-records {student: student, phase: phase} {
      reward-amount: reward-amount,
      reward-type: "early-payment",
      claimed-block: current-block,
      badge-token-id: (some badge-id)
    })
    
    ;; Store badge metadata
    (map-set badge-metadata badge-id {
      student: student,
      phase: phase,
      reward-amount: reward-amount,
      earned-block: current-block,
      badge-type: "Early Payment Champion"
    })
    
    ;; Update student stats
    (map-set student-reward-stats student {
      total-rewards-earned: (+ (get total-rewards-earned current-stats) reward-amount),
      total-penalties-paid: (get total-penalties-paid current-stats),
      early-payments: (+ (get early-payments current-stats) u1),
      late-payments: (get late-payments current-stats),
      badge-count: (+ (get badge-count current-stats) u1)
    })
    
    ;; Increment badge counter
    (var-set next-badge-id (+ badge-id u1))
    
    (ok {
      student: student,
      phase: phase,
      reward-amount: reward-amount,
      badge-id: badge-id,
      discount-applied: reward-amount
    })
  )
)

;; Apply late payment penalty
(define-public (apply-late-payment-penalty
  (student principal)
  (phase uint)
  (base-payment-amount uint)
)
  (let (
    (deadline-info (unwrap! (get-payment-deadline student phase) ERR_PAYMENT_NOT_DUE))
    (current-block stacks-block-height)
    (grace-deadline (get grace-deadline deadline-info))
    (days-late (calculate-days-late grace-deadline current-block))
    (penalty-amount (calculate-late-penalty base-payment-amount days-late))
    (current-stats (get-student-stats student))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (> current-block grace-deadline) ERR_PAYMENT_NOT_DUE)
    (asserts! (is-none (get-penalty-record student phase)) ERR_PENALTY_ALREADY_APPLIED)
    
    ;; Record penalty
    (map-set penalty-records {student: student, phase: phase} {
      penalty-amount: penalty-amount,
      applied-block: current-block,
      days-late: days-late,
      paid: false
    })
    
    ;; Update student stats
    (map-set student-reward-stats student {
      total-rewards-earned: (get total-rewards-earned current-stats),
      total-penalties-paid: (+ (get total-penalties-paid current-stats) penalty-amount),
      early-payments: (get early-payments current-stats),
      late-payments: (+ (get late-payments current-stats) u1),
      badge-count: (get badge-count current-stats)
    })
    
    (ok {
      student: student,
      phase: phase,
      penalty-amount: penalty-amount,
      days-late: days-late,
      total-amount-due: (+ base-payment-amount penalty-amount)
    })
  )
)

;; Mark penalty as paid
(define-public (mark-penalty-paid (student principal) (phase uint))
  (let ((penalty-info (unwrap! (get-penalty-record student phase) ERR_STUDENT_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (not (get paid penalty-info)) ERR_PENALTY_ALREADY_APPLIED)
    
    (map-set penalty-records {student: student, phase: phase}
      (merge penalty-info {paid: true})
    )
    
    (ok {
      student: student,
      phase: phase,
      penalty-amount: (get penalty-amount penalty-info),
      marked-paid: true
    })
  )
)

;; Get comprehensive student payment summary
(define-public (get-student-payment-summary (student principal))
  (let (
    (stats (get-student-stats student))
    (reg-status (get-payment-status student PHASE_REGISTRATION))
    (tuition-status (get-payment-status student PHASE_TUITION))
    (exam-status (get-payment-status student PHASE_EXAMS))
    (clearance-status (get-payment-status student PHASE_CLEARANCE))
  )
    (ok {
      student: student,
      stats: stats,
      phase-statuses: {
        registration: reg-status,
        tuition: tuition-status,
        exams: exam-status,
        clearance: clearance-status
      },
      net-savings: (- (get total-rewards-earned stats) (get total-penalties-paid stats))
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

;; Emergency function to adjust penalty/reward rates
(define-public (emergency-reset-student-stats (student principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-delete student-reward-stats student)
    (ok {reset-student: student})
  )
)
