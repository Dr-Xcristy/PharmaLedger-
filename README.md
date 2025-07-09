# PharmaLedger Smart Contract

A blockchain-based pharmaceutical supply chain tracking system built on the Stacks blockchain using Clarity smart contracts. This contract provides a transparent, immutable ledger for tracking drug batches from manufacture through distribution.

## Features

- **Trusted Entity Management**: Registration and management of manufacturers and distributors
- **Drug Type Registry**: Secure registration of pharmaceutical drug types with metadata
- **Batch Tracking**: Creation and tracking of individual drug batches
- **Custody Chain**: Transparent transfer of custody with complete audit trail
- **Immutable History**: Permanent record of all transactions and ownership changes
- **Access Control**: Role-based permissions for different supply chain participants

## Table of Contents

- [Getting Started](#getting-started)
- [Contract Architecture](#contract-architecture)
- [Functions](#functions)
- [Data Structures](#data-structures)
- [Error Codes](#error-codes)
- [Usage Examples](#usage-examples)
- [Security Considerations](#security-considerations)
- [Testing](#testing)
- [Deployment](#deployment)
- [Contributing](#contributing)

## Getting Started

### Prerequisites

- [Clarinet CLI](https://github.com/hirosystems/clarinet) v0.31.1 or higher
- [Stacks CLI](https://github.com/hirosystems/stacks.js) (for deployment)
- Basic understanding of Clarity smart contracts

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd pharma-ledger
```

2. Install Clarinet:
```bash
# Install via npm
npm install -g @hirosystems/clarinet

# Or install via homebrew (macOS)
brew install clarinet
```

3. Verify installation:
```bash
clarinet --version
```

### Quick Start

1. Check the contract for errors:
```bash
clarinet check
```

2. Run tests:
```bash
clarinet test
```

3. Deploy to local testnet:
```bash
clarinet integrate
```

## Contract Architecture

The PharmaLedger contract follows a hierarchical structure:

```
Contract Administrator
├── Manufacturers (trusted entities)
│   ├── Register Drug Types
│   └── Create Drug Batches
└── Distributors (trusted entities)
    └── Receive Batch Transfers

Drug Types
├── Unique identifiers
├── Metadata (name, formula)
└── Associated manufacturer

Drug Batches
├── Linked to drug type
├── Manufacturing & expiration dates
├── Current owner
├── Metadata URI
└── Complete custody history
```

## Functions

### Administrative Functions

#### `add-manufacturer`
Registers a new trusted manufacturer.

**Parameters:**
- `new-manufacturer` (principal): The manufacturer's principal address

**Returns:** `(response bool uint)`

**Access:** Contract administrator only

#### `add-distributor`
Registers a new trusted distributor.

**Parameters:**
- `new-distributor` (principal): The distributor's principal address

**Returns:** `(response bool uint)`

**Access:** Contract administrator only

### Core Functions

#### `register-drug-type`
Allows registered manufacturers to define new drug types.

**Parameters:**
- `name` (buff 32): Brand name of the drug
- `formula` (buff 64): Chemical formula or active ingredient

**Returns:** `(response uint uint)` - The new drug-id

**Access:** Registered manufacturers only

**Validations:**
- Caller must be a registered manufacturer
- Name must not be empty
- Formula must not be empty

#### `create-drug-batch`
Creates a new batch of a registered drug type.

**Parameters:**
- `drug-id` (uint): ID of the drug type
- `mfg-date` (uint): Manufacturing date (Unix timestamp)
- `exp-date` (uint): Expiration date (Unix timestamp)
- `metadata-uri` (string-ascii 256): Link to off-chain batch data

**Returns:** `(response uint uint)` - The new batch-id

**Access:** Original manufacturer of the drug type only

**Validations:**
- Caller must be the original manufacturer
- Expiration date must be after manufacturing date
- Metadata URI must not be empty

#### `transfer-batch-custody`
Transfers ownership of a drug batch to a new custodian.

**Parameters:**
- `batch-id` (uint): ID of the batch to transfer
- `new-custodian` (principal): New owner's principal address

**Returns:** `(response bool uint)`

**Access:** Current batch owner only

**Validations:**
- Caller must be current batch owner
- New custodian must be a registered manufacturer or distributor
- Custody history must not be full (max 200 entries)

### Read-Only Functions

#### `get-drug-type-info`
Retrieves information about a specific drug type.

**Parameters:**
- `drug-id` (uint): The drug type ID

**Returns:** `(optional {...})` - Drug type information or none

#### `get-batch-info`
Retrieves information about a specific drug batch.

**Parameters:**
- `batch-id` (uint): The batch ID

**Returns:** `(optional {...})` - Batch information or none

#### `get-batch-custody-history`
Retrieves the complete custody history of a batch.

**Parameters:**
- `batch-id` (uint): The batch ID

**Returns:** `(optional (list 200 principal))` - List of all owners

#### `is-manufacturer`
Checks if a principal is a registered manufacturer.

**Parameters:**
- `who` (principal): Principal to check

**Returns:** `bool`

#### `is-distributor`
Checks if a principal is a registered distributor.

**Parameters:**
- `who` (principal): Principal to check

**Returns:** `bool`

#### `get-total-drug-types`
Returns the total number of registered drug types.

**Returns:** `uint`

#### `get-total-batches`
Returns the total number of created batches.

**Returns:** `uint`

## Data Structures

### Drug Type
```clarity
{
  name: (buff 32),           // Drug brand name
  formula: (buff 64),        // Chemical formula
  manufacturer: principal    // Original manufacturer
}
```

### Drug Batch
```clarity
{
  drug-id: uint,                      // Reference to drug type
  mfg-date: uint,                     // Manufacturing date
  exp-date: uint,                     // Expiration date
  current-owner: principal,           // Current custodian
  metadata-uri: (string-ascii 256)    // Off-chain metadata link
}
```

### Custody History
```clarity
(list 200 principal)  // Chronological list of owners
```

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u101 | ERR-UNAUTHORIZED | Caller lacks required permissions |
| u102 | ERR-MANUFACTURER-NOT-FOUND | Manufacturer not registered |
| u103 | ERR-DISTRIBUTOR-NOT-FOUND | Distributor not registered |
| u104 | ERR-DRUG-TYPE-NOT-FOUND | Drug type doesn't exist |
| u105 | ERR-BATCH-NOT-FOUND | Batch doesn't exist |
| u106 | ERR-NOT-BATCH-OWNER | Caller is not the batch owner |
| u107 | ERR-INVALID-CUSTODIAN | New custodian not registered |
| u108 | ERR-ALREADY-REGISTERED | Entity already registered |
| u109 | ERR-EMPTY-METADATA | Metadata cannot be empty |
| u110 | ERR-CUSTODY-HISTORY-FULL | Custody history at maximum capacity |
| u111 | ERR-INVALID-NAME | Drug name is invalid or empty |
| u112 | ERR-INVALID-FORMULA | Formula is invalid or empty |
| u113 | ERR-INVALID-DATE | Invalid date range |
| u114 | ERR-INVALID-METADATA-URI | Metadata URI is invalid or empty |

## Usage Examples

### Setting Up the System

```clarity
;; 1. Administrator adds manufacturers
(contract-call? .pharma-ledger add-manufacturer 'SP1234...MANUFACTURER)
(contract-call? .pharma-ledger add-distributor 'SP5678...DISTRIBUTOR)

;; 2. Manufacturer registers a drug type
(contract-call? .pharma-ledger register-drug-type 
  "Aspirin" 
  "C9H8O4")

;; 3. Manufacturer creates a batch
(contract-call? .pharma-ledger create-drug-batch 
  u1                    ;; drug-id
  u1640995200          ;; mfg-date (2022-01-01)
  u1735689600          ;; exp-date (2025-01-01)
  "https://ipfs.io/batch-123-data")

;; 4. Transfer custody to distributor
(contract-call? .pharma-ledger transfer-batch-custody 
  u1                    ;; batch-id
  'SP5678...DISTRIBUTOR)
```

### Querying Information

```clarity
;; Get drug type information
(contract-call? .pharma-ledger get-drug-type-info u1)

;; Get batch information
(contract-call? .pharma-ledger get-batch-info u1)

;; Check custody history
(contract-call? .pharma-ledger get-batch-custody-history u1)

;; Verify entity status
(contract-call? .pharma-ledger is-manufacturer 'SP1234...MANUFACTURER)
```

## Security Considerations

### Access Control
- Only the contract administrator can register manufacturers and distributors
- Only registered manufacturers can create drug types and batches
- Only the current batch owner can transfer custody
- New custodians must be registered entities

### Input Validation
- All user inputs are validated before processing
- Date ranges are checked for logical consistency
- Empty or invalid data is rejected
- Metadata URIs are required and validated

### Immutability
- Drug types and batches cannot be modified after creation
- Custody history is append-only and cannot be altered
- All transactions are permanently recorded on the blockchain

### Limitations
- Maximum 200 custody transfers per batch
- Fixed-size buffers for names and formulas
- No batch expiration enforcement (handled off-chain)

## Testing

### Unit Tests

Run the test suite:
```bash
clarinet test
```

### Integration Tests

Test against local blockchain:
```bash
clarinet integrate
```

### Test Coverage

The contract includes comprehensive tests for:
- Administrative functions
- Drug type registration
- Batch creation and transfer
- Error handling
- Edge cases

## Deployment

### Local Testnet

1. Start local blockchain:
```bash
clarinet integrate
```

2. Deploy contract:
```bash
clarinet deploy --testnet
```

### Mainnet Deployment

1. Configure your deployment settings in `Clarinet.toml`
2. Deploy to mainnet:
```bash
clarinet deploy --mainnet
```

**Note:** Ensure thorough testing before mainnet deployment.

## Contributing

### Development Workflow

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `clarinet test`
5. Check for errors: `clarinet check`
6. Submit a pull request

### Code Style

- Follow Clarity best practices
- Use descriptive variable names
- Add comprehensive comments
- Validate all inputs
- Handle errors gracefully

### Reporting Issues

Please report bugs and feature requests through GitHub issues.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Version History

- **v1.0.1** - Added comprehensive input validation, fixed list length issues
- **v1.0.0** - Initial release with core functionality

## Support

For questions, issues, or contributions:
- GitHub Issues: [Create an issue](https://github.com/your-repo/pharma-ledger/issues)
- Documentation: [Clarity Documentation](https://docs.stacks.co/clarity/)
- Community: [Stacks Discord](https://discord.gg/stacks)

---

**Disclaimer:** This smart contract is provided as-is for educational and development purposes. Ensure proper testing and security audits before production use in pharmaceutical supply chains.