;; Assessment Management Contract
;; Manages security assessments, consultant assignments, and client relationships

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ASSESSMENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-INVALID-DATES (err u103))
(define-constant ERR-CONSULTANT-NOT-REGISTERED (err u104))
(define-constant ERR-CLIENT-NOT-REGISTERED (err u105))
(define-constant ERR-ASSESSMENT-ALREADY-EXISTS (err u106))

;; Data Variables
(define-data-var next-assessment-id uint u1)
(define-data-var contract-active bool true)

;; Data Maps
(define-map assessments
  { assessment-id: uint }
  {
    client: principal,
    consultant: principal,
    assessment-type: (string-ascii 50),
    status: (string-ascii 20),
    start-date: uint,
    end-date: uint,
    scope: (string-ascii 500),
    findings-count: uint,
    created-at: uint,
    updated-at: uint
  }
)

(define-map registered-consultants
  { consultant: principal }
  {
    name: (string-ascii 100),
    specialization: (string-ascii 100),
    certification-level: uint,
    active-assessments: uint,
    total-assessments: uint,
    reputation-score: uint,
    registered-at: uint
  }
)

(define-map registered-clients
  { client: principal }
  {
    company-name: (string-ascii 100),
    industry: (string-ascii 50),
    compliance-requirements: (string-ascii 200),
    total-assessments: uint,
    active-assessments: uint,
    registered-at: uint
  }
)

(define-map assessment-permissions
  { assessment-id: uint, user: principal }
  { can-view: bool, can-edit: bool }
)

;; Private Functions
(define-private (is-valid-status (status (string-ascii 20)))
  (or
    (is-eq status "scheduled")
    (is-eq status "in-progress")
    (is-eq status "completed")
    (is-eq status "cancelled")
    (is-eq status "on-hold")
  )
)

(define-private (is-valid-assessment-type (assessment-type (string-ascii 50)))
  (or
    (is-eq assessment-type "penetration-test")
    (is-eq assessment-type "vulnerability-scan")
    (is-eq assessment-type "security-audit")
    (is-eq assessment-type "compliance-review")
    (is-eq assessment-type "incident-response")
    (is-eq assessment-type "security-training")
  )
)

(define-private (has-assessment-permission (assessment-id uint) (user principal) (permission (string-ascii 10)))
  (let ((perms (map-get? assessment-permissions { assessment-id: assessment-id, user: user })))
    (match perms
      perm-data (if (is-eq permission "view")
                   (get can-view perm-data)
                   (get can-edit perm-data))
      false
    )
  )
)

;; Public Functions

;; Register a new consultant
(define-public (register-consultant
  (name (string-ascii 100))
  (specialization (string-ascii 100))
  (certification-level uint))
  (let ((consultant tx-sender))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> certification-level u0) ERR-NOT-AUTHORIZED)
    (asserts! (<= certification-level u5) ERR-NOT-AUTHORIZED)
    (map-set registered-consultants
      { consultant: consultant }
      {
        name: name,
        specialization: specialization,
        certification-level: certification-level,
        active-assessments: u0,
        total-assessments: u0,
        reputation-score: u50,
        registered-at: block-height
      }
    )
    (ok consultant)
  )
)

;; Register a new client
(define-public (register-client
  (company-name (string-ascii 100))
  (industry (string-ascii 50))
  (compliance-requirements (string-ascii 200)))
  (let ((client tx-sender))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (map-set registered-clients
      { client: client }
      {
        company-name: company-name,
        industry: industry,
        compliance-requirements: compliance-requirements,
        total-assessments: u0,
        active-assessments: u0,
        registered-at: block-height
      }
    )
    (ok client)
  )
)

;; Create a new security assessment
(define-public (create-assessment
  (consultant principal)
  (assessment-type (string-ascii 50))
  (start-date uint)
  (end-date uint)
  (scope (string-ascii 500)))
  (let (
    (assessment-id (var-get next-assessment-id))
    (client tx-sender)
  )
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? registered-clients { client: client })) ERR-CLIENT-NOT-REGISTERED)
    (asserts! (is-some (map-get? registered-consultants { consultant: consultant })) ERR-CONSULTANT-NOT-REGISTERED)
    (asserts! (is-valid-assessment-type assessment-type) ERR-INVALID-STATUS)
    (asserts! (< start-date end-date) ERR-INVALID-DATES)
    (asserts! (>= start-date block-height) ERR-INVALID-DATES)

    ;; Create the assessment
    (map-set assessments
      { assessment-id: assessment-id }
      {
        client: client,
        consultant: consultant,
        assessment-type: assessment-type,
        status: "scheduled",
        start-date: start-date,
        end-date: end-date,
        scope: scope,
        findings-count: u0,
        created-at: block-height,
        updated-at: block-height
      }
    )

    ;; Set permissions
    (map-set assessment-permissions
      { assessment-id: assessment-id, user: client }
      { can-view: true, can-edit: true }
    )
    (map-set assessment-permissions
      { assessment-id: assessment-id, user: consultant }
      { can-view: true, can-edit: true }
    )

    ;; Update counters
    (var-set next-assessment-id (+ assessment-id u1))

    ;; Update client stats
    (match (map-get? registered-clients { client: client })
      client-data (map-set registered-clients
        { client: client }
        (merge client-data {
          total-assessments: (+ (get total-assessments client-data) u1),
          active-assessments: (+ (get active-assessments client-data) u1)
        })
      )
      false
    )

    ;; Update consultant stats
    (match (map-get? registered-consultants { consultant: consultant })
      consultant-data (map-set registered-consultants
        { consultant: consultant }
        (merge consultant-data {
          total-assessments: (+ (get total-assessments consultant-data) u1),
          active-assessments: (+ (get active-assessments consultant-data) u1)
        })
      )
      false
    )

    (ok assessment-id)
  )
)

;; Update assessment status
(define-public (update-assessment-status
  (assessment-id uint)
  (new-status (string-ascii 20)))
  (let ((assessment (unwrap! (map-get? assessments { assessment-id: assessment-id }) ERR-ASSESSMENT-NOT-FOUND)))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    (asserts! (or
      (is-eq tx-sender (get client assessment))
      (is-eq tx-sender (get consultant assessment))
      (is-eq tx-sender CONTRACT-OWNER)
    ) ERR-NOT-AUTHORIZED)

    ;; Update assessment
    (map-set assessments
      { assessment-id: assessment-id }
      (merge assessment {
        status: new-status,
        updated-at: block-height
      })
    )

    ;; Update active assessment counters if completing or cancelling
    (if (or (is-eq new-status "completed") (is-eq new-status "cancelled"))
      (begin
        ;; Update client active count
        (match (map-get? registered-clients { client: (get client assessment) })
          client-data (map-set registered-clients
            { client: (get client assessment) }
            (merge client-data {
              active-assessments: (if (> (get active-assessments client-data) u0)
                                    (- (get active-assessments client-data) u1)
                                    u0)
            })
          )
          false
        )
        ;; Update consultant active count
        (match (map-get? registered-consultants { consultant: (get consultant assessment) })
          consultant-data (map-set registered-consultants
            { consultant: (get consultant assessment) }
            (merge consultant-data {
              active-assessments: (if (> (get active-assessments consultant-data) u0)
                                    (- (get active-assessments consultant-data) u1)
                                    u0)
            })
          )
          false
        )
      )
      true
    )

    (ok true)
  )
)

;; Update findings count
(define-public (update-findings-count
  (assessment-id uint)
  (findings-count uint))
  (let ((assessment (unwrap! (map-get? assessments { assessment-id: assessment-id }) ERR-ASSESSMENT-NOT-FOUND)))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq tx-sender (get consultant assessment)) ERR-NOT-AUTHORIZED)

    (map-set assessments
      { assessment-id: assessment-id }
      (merge assessment {
        findings-count: findings-count,
        updated-at: block-height
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get assessment details
(define-read-only (get-assessment (assessment-id uint))
  (map-get? assessments { assessment-id: assessment-id })
)

;; Get consultant details
(define-read-only (get-consultant (consultant principal))
  (map-get? registered-consultants { consultant: consultant })
)

;; Get client details
(define-read-only (get-client (client principal))
  (map-get? registered-clients { client: client })
)

;; Get next assessment ID
(define-read-only (get-next-assessment-id)
  (var-get next-assessment-id)
)

;; Check if user can view assessment
(define-read-only (can-view-assessment (assessment-id uint) (user principal))
  (has-assessment-permission assessment-id user "view")
)

;; Get assessments by client
(define-read-only (get-client-assessments (client principal))
  (map-get? registered-clients { client: client })
)

;; Get assessments by consultant
(define-read-only (get-consultant-assessments (consultant principal))
  (map-get? registered-consultants { consultant: consultant })
)

;; Admin Functions

;; Emergency pause contract
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active false)
    (ok true)
  )
)

;; Resume contract
(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active true)
    (ok true)
  )
)

;; Update consultant reputation
(define-public (update-consultant-reputation
  (consultant principal)
  (new-score uint))
  (let ((consultant-data (unwrap! (map-get? registered-consultants { consultant: consultant }) ERR-CONSULTANT-NOT-REGISTERED)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-score u100) ERR-NOT-AUTHORIZED)

    (map-set registered-consultants
      { consultant: consultant }
      (merge consultant-data { reputation-score: new-score })
    )
    (ok true)
  )
)
