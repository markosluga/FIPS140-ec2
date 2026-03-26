# FIPS-140 Field Encryption Demo

> **EC2 deployment**
> This repo is for deploying the demo on EC2. It does not support running the stack locally — for local development see [markosluga/FIPS140](https://github.com/markosluga/FIPS140).
>
> The stack is deployed automatically on instance boot via a systemd service. Use the spin-up scripts below to launch a new instance.

## TL;DR

This is a 2-step process:

1. **Phase 1:** NGINX intercepts the request, signs and calls AWS KMS directly to generate an ephemeral data key (DEK), encrypts the sensitive field with AES-256-GCM using the WebCrypto API, and forwards only the ciphertext envelope to the backend. The DEK never leaves NGINX memory.
2. **Phase 2:** The backend receives the encrypted payload, calls KMS directly to decrypt the envelope, and logs the recovered plaintext — demonstrating the full round-trip.

This demonstrates a way to implement transparent field-level encryption in front of practically any backend service, with NGINX doing all the crypto work inline — no sidecar, no proxy, no extra hop.

**And it's as easy as 1-2!**

## A word of caution

While we follow best practices all the way, the logger is used to demo what is happening and **logs in plain-text** — because it's a demo and we want to show what's happening in the background. If you ever want to reuse any of this code, know that this code as-is is NOT meant for actual production use.

---

## Spinning up an EC2 instance

The spin-up scripts launch a spot instance from the `FIPS140-nginx-demo` launch template. They try each subnet in order and move to the next AZ automatically if Spot capacity is unavailable. On first boot, the instance installs Docker, clones this repo, and starts the stack via systemd — no manual setup needed.

### First-time infrastructure setup

Before running the scripts you need to deploy the CloudFormation stack and configure your local copies of the scripts.

**1. Deploy the CloudFormation stack** (creates the IAM role, instance profile, and launch template):

```bash
aws cloudformation deploy \
  --region us-east-1 \
  --stack-name FIPS140-nginx-demo \
  --template-file infra/cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      AmiId=<ami-id> \
      KeyName=<key-pair-name> \
      SubnetId=<subnet-id> \
      SecurityGroupId=<sg-id>
```

Use the commands below to find or create the required values.

**Find the latest Ubuntu 24.04 LTS AMI:**
```bash
aws ec2 describe-images --region us-east-1 --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
            "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
```

**List key pairs:**
```bash
aws ec2 describe-key-pairs --region us-east-1 \
  --query "KeyPairs[*].KeyName" --output table
```

**List subnets:**
```bash
aws ec2 describe-subnets --region us-east-1 \
  --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}" --output table
```

**List security groups:**
```bash
aws ec2 describe-security-groups --region us-east-1 \
  --query "SecurityGroups[*].{GroupId:GroupId,Name:GroupName,VPC:VpcId}" --output table
```

**Create a security group with HTTP (port 80) open:**
```bash
SG_ID=$(aws ec2 create-security-group --region us-east-1 \
  --group-name "my-demo-sg" --description "Allow HTTP" --vpc-id <vpc-id> \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --region us-east-1 \
  --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
```

**2. Configure your local spin-up script**

The committed scripts are sanitized templates. Copy to a local version (git-ignored) and fill in your values:

```bash
# Bash
cp spin-up.sh spin-up.local.sh
```
```powershell
# PowerShell
Copy-Item spin-up.ps1 spin-up.local.ps1
```

Edit the local copy and replace the `subnet-XXXXXX` and `sg-XXXXXX` placeholders with your real IDs. Add one subnet per AZ you want to use — the script will try them in order and fall back automatically on Spot capacity errors.

### Running the scripts

**PowerShell (Windows):**
```powershell
.\spin-up.local.ps1
```

**Bash (Linux/macOS):**
```bash
bash spin-up.local.sh
```

> **Note:** The scripts use `--profile demos`. Change the `--profile` flag to match your AWS CLI profile, or remove it to use the default credential chain.

Once the instance is running, open `http://<public-ip>` in your browser.

---

## Prerequisites

- Docker + Docker Compose
- AWS credentials with KMS access (`kms:GenerateDataKey`, `kms:Decrypt`, `kms:DescribeKey`)

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
2. **Phase 2** — click Decrypt to retrieve the plaintext via KMS.

---

## Architecture

```
Browser → NGINX (SigV4 + WebCrypto) → Backend (KMS direct) → Browser
                    ↕                          ↕
               AWS KMS                     AWS KMS
```

| Service  | Port | Role                                                    |
|----------|------|---------------------------------------------------------|
| nginx    | 80   | Encryption proxy + Web UI — calls KMS directly via njs  |
| backend  | 5000 | Receives encrypted payload, decrypts via KMS, echoes back |

## How encryption works

NGINX handles the full encrypt/decrypt path inline using two standard APIs — no sidecar process required:

**Encrypt (Phase 1):**
1. NGINX intercepts the POST request
2. njs calls `KMS.GenerateDataKey` directly, signed with **AWS SigV4** (implemented in `crypto.subtle` HMAC-SHA256)
3. njs encrypts the field locally with **AES-256-GCM** via the WebCrypto API (`crypto.subtle.encrypt`)
4. The plaintext DEK is zeroed immediately after use
5. The ciphertext envelope (`ENC_V1_...`) — containing the encrypted DEK, IV, and ciphertext — is forwarded to the backend in place of the plaintext value

**Decrypt (Phase 2):**
1. The frontend sends the stored ciphertext back to NGINX `/api/decrypt`
2. njs unpacks the envelope, sends the encrypted DEK to `KMS.Decrypt`
3. njs decrypts locally with AES-256-GCM and returns the plaintext

**Backend:**
The Flask backend receives the encrypted payload, calls `KMS.Decrypt` directly using `kms_client.py`, logs the recovered plaintext, and echoes the decrypted data back — demonstrating the full server-side flow independently of NGINX.

## Envelope format

Each encrypted field is a self-contained envelope:

```
ENC_V1_<base64(JSON)>
```

Where the JSON contains:
```json
{
  "v": 1,
  "edk": "<base64 — encrypted DEK, unwrapped by KMS on decrypt>",
  "iv":  "<base64 — 12-byte random nonce>",
  "ct":  "<base64 — AES-256-GCM ciphertext + auth tag>"
}
```

The envelope is portable — decryption only needs the envelope itself and KMS access. No separate key lookup required.

## IAM permissions required

The EC2 instance role needs:

```json
{
  "Effect": "Allow",
  "Action": [
    "kms:GenerateDataKey",
    "kms:Decrypt",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}
```
