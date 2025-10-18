;; School Revenue Tracking
;; Transparent earnings, budgeting, and financial projections

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u500))
(define-constant ERR-INVALID-AMOUNT (err u501))
(define-constant ERR-SCHOOL-NOT-FOUND (err u502))

;; School financial records
(define-map schools
  principal
  {
    name: (string-ascii 100),
    total-earnings: uint,
    current-balance: uint,
    budget-allocated: uint,
    created-at: uint
  }
)

;; Revenue history per school
(define-map revenue-records
  { school: principal, record-id: uint }
  {
    amount: uint,
    source: (string-ascii 64),
    timestamp: uint
  }
)

;; Budget allocations per school
(define-map budget-items
  { school: principal, item-id: uint }
  {
    category: (string-ascii 64),
    amount: uint,
    spent: uint
  }
)

;; Data variables
(define-data-var school-count uint u0)

;; Read-only functions
(define-read-only (get-school-info (school principal))
  (map-get? schools school)
)

(define-read-only (get-revenue-record (school principal) (record-id uint))
  (map-get? revenue-records { school: school, record-id: record-id })
)

(define-read-only (get-budget-item (school principal) (item-id uint))
  (map-get? budget-items { school: school, item-id: item-id })
)

(define-read-only (calculate-available-balance (school principal))
  (match (get-school-info school)
    info
    (let ((current (get current-balance info))
          (allocated (get budget-allocated info)))
      (if (>= current allocated)
        (- current allocated)
        u0))
    u0)
)

(define-read-only (calculate-projection (school principal) (growth-percentage uint))
  (match (get-school-info school)
    info
    (let ((earnings (get total-earnings info)))
      (+ earnings (/ (* earnings growth-percentage) u100)))
    u0)
)

;; Public functions

;; Register school
(define-public (register-school (name (string-ascii 100)))
  (let ((school-principal tx-sender))
    (asserts! (is-none (map-get? schools school-principal)) ERR-UNAUTHORIZED)
    
    (map-set schools school-principal {
      name: name,
      total-earnings: u0,
      current-balance: u0,
      budget-allocated: u0,
      created-at: stacks-block-height
    })
    
    (var-set school-count (+ (var-get school-count) u1))
    (ok true)
  )
)

;; Record revenue
(define-public (record-revenue (amount uint) (source (string-ascii 64)))
  (let ((school tx-sender)
        (school-data (unwrap! (map-get? schools school) ERR-SCHOOL-NOT-FOUND))
        (record-id (var-get school-count)))
    
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Record revenue
    (map-set revenue-records
      { school: school, record-id: record-id }
      {
        amount: amount,
        source: source,
        timestamp: stacks-block-height
      })
    
    ;; Update school totals
    (map-set schools school (merge school-data {
      total-earnings: (+ (get total-earnings school-data) amount),
      current-balance: (+ (get current-balance school-data) amount)
    }))
    
    (var-set school-count (+ record-id u1))
    (ok record-id)
  )
)

;; Allocate budget
(define-public (allocate-budget (category (string-ascii 64)) (amount uint))
  (let ((school tx-sender)
        (school-data (unwrap! (map-get? schools school) ERR-SCHOOL-NOT-FOUND))
        (item-id (var-get school-count)))
    
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (get current-balance school-data)) ERR-INVALID-AMOUNT)
    
    ;; Create budget item
    (map-set budget-items
      { school: school, item-id: item-id }
      {
        category: category,
        amount: amount,
        spent: u0
      })
    
    ;; Update allocated budget
    (map-set schools school (merge school-data {
      budget-allocated: (+ (get budget-allocated school-data) amount)
    }))
    
    (var-set school-count (+ item-id u1))
    (ok item-id)
  )
)

;; Mark budget as spent
(define-public (mark-budget-spent (item-id uint) (amount-spent uint))
  (let ((school tx-sender)
        (budget-item (unwrap! (map-get? budget-items { school: school, item-id: item-id }) ERR-INVALID-AMOUNT)))
    
    (asserts! (<= amount-spent (get amount budget-item)) ERR-INVALID-AMOUNT)
    
    (map-set budget-items
      { school: school, item-id: item-id }
      (merge budget-item {
        spent: (+ (get spent budget-item) amount-spent)
      }))
    
    (ok true)
  )
)

;; Withdraw earnings
(define-public (withdraw-earnings (amount uint))
  (let ((school tx-sender)
        (school-data (unwrap! (map-get? schools school) ERR-SCHOOL-NOT-FOUND)))
    
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (calculate-available-balance school)) ERR-INVALID-AMOUNT)
    
    ;; Update balance
    (map-set schools school (merge school-data {
      current-balance: (- (get current-balance school-data) amount)
    }))
    
    ;; Transfer to school
    (try! (stx-transfer? amount (as-contract tx-sender) school))
    
    (ok amount)
  )
)