# eduflex - Pay-As-You-Go School Fees System

A blockchain-based educational payment system built on Stacks that enables students to pay school fees in installments through a phase-based payment structure.

## 🎓 Overview

EduFlex revolutionizes school fee payments by breaking down total fees into manageable phases, allowing students to pay as they progress through their academic journey. The system ensures transparency, security, and flexibility for both students and educational institutions.

## 🚀 Key Features

### Phase-Based Payment System
- **Registration Phase**: Initial enrollment and registration fees
- **Tuition Phase**: Main academic fees
- **Exams Phase**: Examination and assessment fees  
- **Clearance Phase**: Final clearance and graduation fees

### Core Functionality
- **Student Wallet Management**: Secure STX-based wallet tied to student ID
- **School Integration**: Direct communication with school portals
- **Installment Payments**: Pay fees in phases rather than lump sum
- **Payment History**: Complete transaction tracking
- **Automated Progression**: Automatic advancement to next payment phase

### Security Features
- **Phase Validation**: Cannot skip payment phases
- **Duplicate Prevention**: Cannot pay the same phase twice
- **School Verification**: Only registered schools can collect fees
- **Platform Fee System**: Sustainable 0.5% platform fee

## 🛠️ Technical Stack

- **Blockchain**: Stacks (Bitcoin Layer 2)
- **Smart Contract Language**: Clarity v2.4
- **Development Framework**: Clarinet
- **Testing**: Clarinet Test Framework

## 📋 Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- [Stacks CLI](https://docs.stacks.co/docs/cli) (optional)
- Node.js 16+ (for testing)

## 🚀 Quick Start

### 1. Clone and Setup
\`\`\`bash
git clone <repository-url>
cd eduflex
clarinet check
\`\`\`

### 2. Run Tests
\`\`\`bash
clarinet test
\`\`\`

### 3. Deploy to Testnet
\`\`\`bash
clarinet deploy --testnet
\`\`\`

## 📖 Usage Guide

### For Schools

#### 1. Register School
\`\`\`clarity
(contract-call? .eduflex register-school 
  "University Name"
  u1000000    ;; 1 STX registration fee
  u5000000    ;; 5 STX tuition fee
  u500000     ;; 0.5 STX exam fee
  u200000     ;; 0.2 STX clearance fee
)
\`\`\`

#### 2. Update Fee Structure
\`\`\`clarity
(contract-call? .eduflex update-school-fees 
  u1200000    ;; Updated registration fee
  u5500000    ;; Updated tuition fee
  u600000     ;; Updated exam fee
  u250000     ;; Updated clearance fee
)
\`\`\`

#### 3. Toggle School Status
\`\`\`clarity
(contract-call? .eduflex toggle-school-status) ;; Activate/deactivate school
\`\`\`

### For Students

#### 1. Register as Student
\`\`\`clarity
(contract-call? .eduflex register-student 'SP1SCHOOL_ADDRESS)
\`\`\`

#### 2. Top Up Wallet
\`\`\`clarity
(contract-call? .eduflex top-up-wallet u10000000) ;; Add 10 STX to wallet
\`\`\`

#### 3. Pay Phase Fees
\`\`\`clarity
;; Pay registration fee (Phase 1)
(contract-call? .eduflex pay-phase u1)

;; Pay tuition fee (Phase 2) - only after registration
(contract-call? .eduflex pay-phase u2)

;; Pay exam fee (Phase 3) - only after tuition
(contract-call? .eduflex pay-phase u3)

;; Pay clearance fee (Phase 4) - only after exams
(contract-call? .eduflex pay-phase u4)
\`\`\`

## 🔍 Contract Functions

### Read-Only Functions
- \`get-student-info\`: Get student details and payment status
- \`get-student-by-id\`: Look up student by ID number
- \`get-school-info\`: Get school details and fee structure
- \`get-payment-history\`: Get payment history for specific phase
- \`get-school-earnings\`: Get school earnings by phase
- \`calculate-total-fees\`: Calculate total fees for a school

### Public Functions
- \`register-school\`: Register new educational institution
- \`register-student\`: Register new student with school
- \`top-up-wallet\`: Add STX to student wallet
- \`pay-phase\`: Pay for specific academic phase
- \`update-school-fees\`: Update school fee structure

### Admin Functions
- \`set-platform-fee-rate\`: Update platform fee percentage
- \`toggle-contract-status\`: Pause/unpause contract
- \`emergency-withdraw\`: Emergency fund withdrawal

## 📊 Payment Phases

| Phase | Description | Prerequisites |
|-------|-------------|---------------|
| 1 | Registration | None (entry point) |
| 2 | Tuition | Must complete Registration |
| 3 | Exams | Must complete Tuition |
| 4 | Clearance | Must complete Exams |

## 🧪 Testing

The contract includes comprehensive tests covering:
- School registration and fee setting
- Student registration and wallet management
- Phase-based payment progression
- Payment validation and error handling
- Duplicate payment prevention

Run tests with:
\`\`\`bash
clarinet test
\`\`\`

## 🔒 Security Features

- **Sequential Payment Enforcement**: Students must pay phases in order
- **Duplicate Payment Prevention**: Cannot pay the same phase twice
- **School Verification**: Only active, registered schools can collect fees
- **Wallet Security**: Student wallets are tied to their blockchain identity
- **Platform Fee Protection**: Reasonable fee structure with maximum limits

## 💡 Use Cases

### Primary Use Cases
- **Universities**: Semester-based fee collection
- **Technical Schools**: Module-based payment structure
- **Training Institutes**: Course progression payments
- **Certification Programs**: Phase-based certification fees

### Benefits for Students
- **Flexible Payments**: Pay as you progress through studies
- **Transparent Fees**: Clear breakdown of all costs
- **Secure Transactions**: Blockchain-based payment security
- **Payment History**: Complete transaction records

### Benefits for Schools
- **Automated Collection**: Smart contract handles payments
- **Reduced Defaults**: Students pay incrementally
- **Real-time Tracking**: Instant payment notifications
- **Lower Processing Costs**: Minimal platform fees

## 🗺️ Roadmap

### Phase 2 Features
- **Scholarship Integration**: Smart contract-based scholarships
- **Payment Plans**: Custom installment schedules
- **Multi-token Support**: Accept various cryptocurrencies
- **Mobile App**: Student and school mobile applications
- **Analytics Dashboard**: Payment and enrollment analytics

### Phase 3 Features
- **Academic Records**: Blockchain-based transcripts
- **Credential Verification**: Tamper-proof certificates
- **Multi-school Support**: Students across multiple institutions
- **Loan Integration**: Educational loan smart contracts

## 📄 License

MIT License - see LICENSE file for details

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Add comprehensive tests
4. Ensure all tests pass
5. Submit a pull request

## 📞 Support

For issues and questions:
- Create an issue on GitHub
- Join our Discord community
- Email: support@eduflex.edu

---

**eduflex** - Making education accessible through flexible, blockchain-based payment solutions.
