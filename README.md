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

## NGINX implementation in njs (default)

The default implementation uses **njs (NGINX JavaScript)** — the `ngx_http_js_module` module bundled with standard `nginx:alpine`. The encryption logic lives in `nginx/js/encryption_module.js` and is loaded via `nginx/Dockerfile.njs`.

## NGINX implementation in Lua

A functionally equivalent **Lua** implementation is also included, using OpenResty (`openresty:alpine`) and `lua-resty-http`. The logic lives in `nginx/lua/encryption_module.lua` and is loaded via `nginx/Dockerfile.lua`.

To switch to the Lua implementation, edit `docker-compose.yml` and change the nginx service's `dockerfile` and `volumes`:

```yaml
  nginx:
    build:
      context: nginx
      dockerfile: Dockerfile.lua        # was: Dockerfile.njs
    ...
    volumes:
      - ./nginx/lua:/usr/local/openresty/nginx/lua:ro     # was: ./nginx/js:/etc/nginx/js:ro
      - ./nginx/html:/usr/local/openresty/nginx/html:ro   # was: ./nginx/html:/usr/share/nginx/html:ro
      - ./config.yaml:/etc/nginx/config.yaml:ro
```
