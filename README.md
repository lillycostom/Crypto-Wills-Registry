# 🏛️ Crypto Wills Registry Smart Contract

A secure and transparent way to manage digital wills on the Stacks blockchain.

## 📝 Overview

The Crypto Wills Registry allows users to create, manage, and execute digital wills using blockchain technology. Each will is represented as an NFT and contains:

- IPFS hash of the encrypted will document
- List of authorized witnesses
- Required number of witness signatures
- Execution block height
- Designated beneficiary

## 🔑 Key Features

- **NFT-Based Wills**: Each will is a unique NFT owned by the testator
- **Multi-Signature Validation**: Requires multiple witness signatures
- **Time-Locked Execution**: Wills can only be executed after a specified block height
- **Revocation Support**: Testators can revoke their will if needed

## 🛠️ Functions

### Creating and Managing Wills

- `register-will`: Create a new will NFT
- `revoke-will`: Deactivate an existing will
- `witness-sign`: Witnesses can sign a will
- `execute-will`: Transfer will NFT to beneficiary when conditions are met

### Read-Only Functions

- `get-will`: Retrieve will details
- `get-witness-status`: Check if a witness has signed
- `is-valid-witness`: Verify witness authorization
- `count-witness-signatures`: Count total signatures

## 💻 Usage Example

```clarity
;; Register a new will
(contract-call? .crypto-wills-registry register-will 
    "QmWWQSuPMS6aXCbZKpEjPHPUZN2NjB3YrhJTHsV4X3vb2t"
    (list tx-sender witness1 witness2)
    u2
    u100000
    beneficiary-address)

;; Witness signing
(contract-call? .crypto-wills-registry witness-sign u1)

;; Execute will
(contract-call? .crypto-wills-registry execute-will u1)
```

## ⚠️ Requirements

- Stacks 2.0
- Clarinet
- At least 2 witnesses per will

## 🔒 Security

- Only authorized witnesses can sign
- Execution requires minimum witness signatures
- Time-locked execution mechanism
- Only testator can revoke will
```
