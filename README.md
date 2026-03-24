# FIPS-140 Field Encryption Demo

> **EC2 deployment**
> This repo is for deploying the demo on EC2. It does not support running the stack locally — for local development see [markosluga/FIPS140](https://github.com/markosluga/FIPS140).
>
> The stack is deployed automatically on instance boot via a systemd service. Use the spin-up scripts below to launch a new instance.

## TL:DR

This is a 3 step process:
1. Phase 1: Demonstrates field-level encryption via AWS KMS, transparent to the app. NGINX intercepts requests, encrypts sensitive fields before they are sent to the backend.
2. Intermediate step: Key cache flush to ensure key needs to be pulled by the back-end from KMS
3. Phase 2: Back-end pulls the key and decrypts.

We're demonstrating a way to implement end-to-end encryption with practically any back-end service, KMS is just used as an example.

**And it's asy as 1-2-3!**

## A word of caution

While we follow best practices all the way, the logger is used to demo what is happening and **logs in plain-text** - because it's a demo and we want to show what's happening in the background - if you EVER want to reuse any of this code know that this code as-is, is NOT in any sense meant for actual use or even production.

## Spinning up an EC2 instance

The spin-up scripts launch a spot instance from the `FIPS140-nginx-demo` launch template. They automatically resolve the latest Ubuntu 24.04 LTS AMI at run time. On first boot, the instance installs Docker, clones this branch, and starts the stack via systemd.

**PowerShell (Windows):**
```powershell
.\spin-up.ps1
```

**Bash (Linux/macOS):**
```bash
bash spin-up.sh
```

> **Note:** The scripts use `--profile demos`. If you are using default AWS credentials or a different profile, remove or change the `--profile` flag in the script before running.

Once the instance is running, open `http://<public-ip>` in your browser.

---

## Prerequisites

- Docker + Docker Compose
- AWS credentials with KMS access

## Setup

```bash
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
export AWS_SESSION_TOKEN=your-token  # if using temporary credentials
```

Create a KMS key and alias:

```bash
KEY_ID=$(aws kms create-key --description "demo-field-encryption" --query 'KeyMetadata.KeyId' --output text)
aws kms create-alias --alias-name alias/demo-field-encryption --target-key-id $KEY_ID
```

## Run

```bash
docker-compose up
```

Open [http://localhost](http://localhost).

## Usage

1. **Phase 1** — enter a credit card number and click Encrypt. Use any [Stripe test card](https://docs.stripe.com/testing) e.g. `4242 4242 4242 4242`.
2. **Flush** — clear the key cache to force a fresh KMS call on decrypt.
3. **Phase 2** — click Decrypt to retrieve the plaintext via KMS.

## Architecture

```
Browser → NGINX (encrypt) → Backend → NGINX (decrypt) → Browser
                ↕                           ↕
           KMS Bridge                  KMS Bridge
                ↕                           ↕
            AWS KMS                     AWS KMS
```

| Service     | Port | Role                        |
|-------------|------|-----------------------------|
| nginx       | 80   | Encryption proxy + Web UI   |
| backend     | 5000 | Echo API                    |
| kms-bridge  | 5001 | AWS KMS HTTP bridge         |
