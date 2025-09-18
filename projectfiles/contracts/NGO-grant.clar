;; Smart contract for transparent educational funding and sponsorship management

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_STUDENT_NOT_FOUND (err u501))
(define-constant ERR_NGO_NOT_FOUND (err u502))
(define-constant ERR_INSUFFICIENT_FUNDS (err u503))
(define-constant ERR_INVALID_AMOUNT (err u504))
(define-constant ERR_APPLICATION_NOT_FOUND (err u505))
(define-constant ERR_APPLICATION_ALREADY_EXISTS (err u506))
(define-constant ERR_SPONSORSHIP_NOT_ACTIVE (err u507))
(define-constant ERR_INVALID_PHASE (err u508))
(define-constant ERR_VOTING_PERIOD_ENDED (err u509))
(define-constant ERR_ALREADY_VOTED (err u510))
(define-constant ERR_CONTRACT_NOT_ACTIVE (err u511))

;; Payment Phases (matching main contract)
(define-constant PHASE_REGISTRATION u1)
(define-constant PHASE_TUITION u2)
(define-constant PHASE_EXAMS u3)
(define-constant PHASE_CLEARANCE u4)

;; Sponsorship Types
(define-constant SPONSORSHIP_PARTIAL u1)
(define-constant SPONSORSHIP_FULL u2)
(define-constant SPONSORSHIP_EMERGENCY u3)

;; Voting Constants
(define-constant VOTING_PERIOD u1008) ;; 7 days in blocks
(define-constant MIN_VOTES_REQUIRED u3)
(define-constant APPROVAL_THRESHOLD u6000) ;; 60% approval needed

;; NFT Definition for Sponsorship Certificates
(define-non-fungible-token sponsorship-certificate uint)

;; Data Variables
(define-data-var contract-active bool true)
(define-data-var next-application-id uint u1)
(define-data-var next-certificate-id uint u1)
(define-data-var total-sponsored-amount uint u0)
(define-data-var main-contract principal tx-sender)

;; Data Maps
(define-map registered-ngos
  principal
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    total-deposited: uint,
    total-sponsored: uint,
    active-sponsorships: uint,
    registration-block: uint,
    verified: bool
  }
)

(define-map sponsorship-applications
  uint
  {
    student: principal,
    student-id: uint,
    school: principal,
    requested-amount: uint,
    phases-to-sponsor: (list 4 uint),
    reason: (string-ascii 500),
    application-block: uint,
    voting-end-block: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    total-voters: uint,
    approved-by: (optional principal)
  }
)

(define-map ngo-fund-pools
  principal
  {
    available-balance: uint,
    reserved-balance: uint,
    total-deposited: uint,
    active-sponsorships: (list 100 uint)
  }
)

(define-map sponsorship-records
  {student: principal, application-id: uint}
  {
    ngo: principal,
    sponsored-amount: uint,
    phases-covered: (list 4 uint),
    start-block: uint,
    completion-block: (optional uint),
    certificate-id: (optional uint),
    status: (string-ascii 20)
  }
)

(define-map dao-votes
  {application-id: uint, voter: principal}
  {
    vote: bool,
    voting-power: uint,
    vote-block: uint
  }
)

(define-map certificate-metadata
  uint
  {
    student: principal,
    ngo: principal,
    application-id: uint,
    sponsored-amount: uint,
    phases-covered: (list 4 uint),
    issue-block: uint,
    certificate-type: (string-ascii 30)
  }
)

(define-map student-sponsorship-history
  principal
  {
    total-received: uint,
    applications-submitted: uint,
    applications-approved: uint,
    sponsoring-ngos: (list 10 principal),
    certificates-earned: uint
  }
)

;; Read-only functions
(define-read-only (get-ngo-info (ngo principal))
  (map-get? registered-ngos ngo)
)

(define-read-only (get-application-info (application-id uint))
  (map-get? sponsorship-applications application-id)
)

(define-read-only (get-ngo-fund-pool (ngo principal))
  (map-get? ngo-fund-pools ngo)
)

(define-read-only (get-sponsorship-record (student principal) (application-id uint))
  (map-get? sponsorship-records {student: student, application-id: application-id})
)

(define-read-only (get-dao-vote (application-id uint) (voter principal))
  (map-get? dao-votes {application-id: application-id, voter: voter})
)

(define-read-only (get-certificate-metadata (certificate-id uint))
  (map-get? certificate-metadata certificate-id)
)

(define-read-only (get-student-sponsorship-history (student principal))
  (default-to 
    {total-received: u0, applications-submitted: u0, applications-approved: u0, sponsoring-ngos: (list), certificates-earned: u0}
    (map-get? student-sponsorship-history student)
  )
)

(define-read-only (get-contract-stats)
  {
    active: (var-get contract-active),
    next-application-id: (var-get next-application-id),
    next-certificate-id: (var-get next-certificate-id),
    total-sponsored-amount: (var-get total-sponsored-amount),
    main-contract: (var-get main-contract)
  }
)

(define-read-only (calculate-voting-result (application-id uint))
  (match (get-application-info application-id)
    app-data
    (let (
      (votes-for (get votes-for app-data))
      (votes-against (get votes-against app-data))
      (total-votes (+ votes-for votes-against))
    )
      {
        votes-for: votes-for,
        votes-against: votes-against,
        total-votes: total-votes,
        approval-rate: (if (> total-votes u0) (/ (* votes-for u10000) total-votes) u0),
        meets-threshold: (and (>= total-votes MIN_VOTES_REQUIRED) 
                             (>= (/ (* votes-for u10000) total-votes) APPROVAL_THRESHOLD)),
        voting-ended: (> stacks-block-height (get voting-end-block app-data))
      }
    )
    {votes-for: u0, votes-against: u0, total-votes: u0, approval-rate: u0, meets-threshold: false, voting-ended: false}
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

(define-private (calculate-total-phase-cost (phases (list 4 uint)) (school principal))
  ;; Simplified calculation - in production would integrate with main contract
  (fold + phases u0)
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

;; Public functions

;; Register NGO for sponsorship program
(define-public (register-ngo 
  (name (string-ascii 100))
  (description (string-ascii 500))
)
  (let ((existing-ngo (get-ngo-info tx-sender)))
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (is-none existing-ngo) ERR_NGO_NOT_FOUND)
    
    (map-set registered-ngos tx-sender {
      name: name,
      description: description,
      total-deposited: u0,
      total-sponsored: u0,
      active-sponsorships: u0,
      registration-block: stacks-block-height,
      verified: false
    })
    
    (map-set ngo-fund-pools tx-sender {
      available-balance: u0,
      reserved-balance: u0,
      total-deposited: u0,
      active-sponsorships: (list)
    })
    
    (ok {
      ngo: tx-sender,
      name: name,
      registration-block: stacks-block-height
    })
  )
)

;; NGO deposits funds for sponsorship
(define-public (deposit-sponsorship-funds (amount uint))
  (let (
    (ngo-info (unwrap! (get-ngo-info tx-sender) ERR_NGO_NOT_FOUND))
    (current-pool (unwrap! (get-ngo-fund-pool tx-sender) ERR_NGO_NOT_FOUND))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    ;; Transfer STX from NGO to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update NGO info
    (map-set registered-ngos tx-sender 
      (merge ngo-info {
        total-deposited: (+ (get total-deposited ngo-info) amount)
      })
    )
    
    ;; Update fund pool
    (map-set ngo-fund-pools tx-sender 
      (merge current-pool {
        available-balance: (+ (get available-balance current-pool) amount),
        total-deposited: (+ (get total-deposited current-pool) amount)
      })
    )
    
    (ok {
      ngo: tx-sender,
      deposited-amount: amount,
      new-available-balance: (+ (get available-balance current-pool) amount)
    })
  )
)

;; Student applies for sponsorship
(define-public (apply-for-sponsorship
  (student-id uint)
  (school principal)
  (requested-amount uint)
  (phases-to-sponsor (list 4 uint))
  (reason (string-ascii 500))
)
  (let (
    (application-id (var-get next-application-id))
    (voting-end-block (+ stacks-block-height VOTING_PERIOD))
    (current-history (get-student-sponsorship-history tx-sender))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (> requested-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> (len phases-to-sponsor) u0) ERR_INVALID_PHASE)
    
    ;; Create application
    (map-set sponsorship-applications application-id {
      student: tx-sender,
      student-id: student-id,
      school: school,
      requested-amount: requested-amount,
      phases-to-sponsor: phases-to-sponsor,
      reason: reason,
      application-block: stacks-block-height,
      voting-end-block: voting-end-block,
      status: "pending",
      votes-for: u0,
      votes-against: u0,
      total-voters: u0,
      approved-by: none
    })
    
    ;; Update student history
    (map-set student-sponsorship-history tx-sender 
      (merge current-history {
        applications-submitted: (+ (get applications-submitted current-history) u1)
      })
    )
    
    ;; Increment application counter
    (var-set next-application-id (+ application-id u1))
    
    (ok {
      application-id: application-id,
      student: tx-sender,
      requested-amount: requested-amount,
      voting-end-block: voting-end-block
    })
  )
)

;; DAO voting on sponsorship applications
(define-public (vote-on-application 
  (application-id uint)
  (vote bool)
  (voting-power uint)
)
  (let (
    (app-data (unwrap! (get-application-info application-id) ERR_APPLICATION_NOT_FOUND))
    (existing-vote (get-dao-vote application-id tx-sender))
    (current-block stacks-block-height)
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (< current-block (get voting-end-block app-data)) ERR_VOTING_PERIOD_ENDED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (> voting-power u0) ERR_INVALID_AMOUNT)
    
    ;; Record vote
    (map-set dao-votes {application-id: application-id, voter: tx-sender} {
      vote: vote,
      voting-power: voting-power,
      vote-block: current-block
    })
    
    ;; Update application vote counts
    (map-set sponsorship-applications application-id 
      (merge app-data {
        votes-for: (if vote (+ (get votes-for app-data) voting-power) (get votes-for app-data)),
        votes-against: (if vote (get votes-against app-data) (+ (get votes-against app-data) voting-power)),
        total-voters: (+ (get total-voters app-data) u1)
      })
    )
    
    (ok {
      application-id: application-id,
      voter: tx-sender,
      vote: vote,
      voting-power: voting-power
    })
  )
)

;; Process approved sponsorship (NGO executes)
(define-public (process-approved-sponsorship (application-id uint))
  (let (
    (app-data (unwrap! (get-application-info application-id) ERR_APPLICATION_NOT_FOUND))
    (voting-result (calculate-voting-result application-id))
    (ngo-pool (unwrap! (get-ngo-fund-pool tx-sender) ERR_NGO_NOT_FOUND))
    (ngo-info (unwrap! (get-ngo-info tx-sender) ERR_NGO_NOT_FOUND))
    (certificate-id (var-get next-certificate-id))
    (student (get student app-data))
    (requested-amount (get requested-amount app-data))
    (current-history (get-student-sponsorship-history student))
  )
    (asserts! (var-get contract-active) ERR_CONTRACT_NOT_ACTIVE)
    (asserts! (get voting-ended voting-result) ERR_VOTING_PERIOD_ENDED)
    (asserts! (get meets-threshold voting-result) ERR_UNAUTHORIZED)
    (asserts! (>= (get available-balance ngo-pool) requested-amount) ERR_INSUFFICIENT_FUNDS)
    (asserts! (is-eq (get status app-data) "pending") ERR_SPONSORSHIP_NOT_ACTIVE)
    
    ;; Transfer sponsorship funds to student
    (try! (as-contract (stx-transfer? requested-amount tx-sender student)))
    
    ;; Mint sponsorship certificate NFT
    (try! (nft-mint? sponsorship-certificate certificate-id student))
    
    ;; Update application status
    (map-set sponsorship-applications application-id 
      (merge app-data {
        status: "approved",
        approved-by: (some tx-sender)
      })
    )
    
    ;; Record sponsorship
    (map-set sponsorship-records {student: student, application-id: application-id} {
      ngo: tx-sender,
      sponsored-amount: requested-amount,
      phases-covered: (get phases-to-sponsor app-data),
      start-block: stacks-block-height,
      completion-block: none,
      certificate-id: (some certificate-id),
      status: "active"
    })
    
    ;; Store certificate metadata
    (map-set certificate-metadata certificate-id {
      student: student,
      ngo: tx-sender,
      application-id: application-id,
      sponsored-amount: requested-amount,
      phases-covered: (get phases-to-sponsor app-data),
      issue-block: stacks-block-height,
      certificate-type: "Educational Sponsorship"
    })
    
    ;; Update NGO fund pool
    (map-set ngo-fund-pools tx-sender 
      (merge ngo-pool {
        available-balance: (- (get available-balance ngo-pool) requested-amount),
        active-sponsorships: (unwrap! (as-max-len? (append (get active-sponsorships ngo-pool) application-id) u100) ERR_APPLICATION_NOT_FOUND)
      })
    )
    
    ;; Update NGO info
    (map-set registered-ngos tx-sender 
      (merge ngo-info {
        total-sponsored: (+ (get total-sponsored ngo-info) requested-amount),
        active-sponsorships: (+ (get active-sponsorships ngo-info) u1)
      })
    )
    
    ;; Update student history
    (map-set student-sponsorship-history student 
      (merge current-history {
        total-received: (+ (get total-received current-history) requested-amount),
        applications-approved: (+ (get applications-approved current-history) u1),
        sponsoring-ngos: (unwrap! (as-max-len? (append (get sponsoring-ngos current-history) tx-sender) u10) ERR_NGO_NOT_FOUND),
        certificates-earned: (+ (get certificates-earned current-history) u1)
      })
    )
    
    ;; Update global stats
    (var-set total-sponsored-amount (+ (var-get total-sponsored-amount) requested-amount))
    (var-set next-certificate-id (+ certificate-id u1))
    
    (ok {
      application-id: application-id,
      student: student,
      ngo: tx-sender,
      sponsored-amount: requested-amount,
      certificate-id: certificate-id
    })
  )
)

;; Get comprehensive sponsorship dashboard
(define-public (get-sponsorship-dashboard (user principal))
  (let (
    (ngo-info (get-ngo-info user))
    (student-history (get-student-sponsorship-history user))
    (ngo-pool (get-ngo-fund-pool user))
  )
    (ok {
      user: user,
      ngo-data: ngo-info,
      student-data: student-history,
      fund-pool: ngo-pool,
      contract-stats: (get-contract-stats)
    })
  )
)

;; Admin functions (contract owner only)
(define-public (verify-ngo (ngo principal))
  (let ((ngo-info (unwrap! (get-ngo-info ngo) ERR_NGO_NOT_FOUND)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (map-set registered-ngos ngo (merge ngo-info {verified: true}))
    (ok {ngo: ngo, verified: true})
  )
)

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

;; Emergency function
(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
    (ok {withdrawn: amount})
  )
)
