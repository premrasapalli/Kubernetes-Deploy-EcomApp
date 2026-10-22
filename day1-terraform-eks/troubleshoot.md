# Troubleshooting Log — enterprise-eks-day1

Date: 2026-10-19
Environment: macOS (darwin_arm64), zsh
Tooling: Terraform v1.14.3, aws-cli/2.36.30, kubectl v1.35.0

---

## Issue 1: `zsh: command not found: #`

### Symptom

Pasting a multi-line command block into the terminal produced:

```
zsh: command not found: #
```

after each `#`-prefixed line (e.g. `# 1. Initialize working directory`).

### Root cause

In interactive zsh, the `INTERACTIVE_COMMENTS` shell option is **off by default**.
Without it, `#` is not treated as a comment character — zsh tries to execute it
as a command, which fails with `command not found: #`.

This only affects **interactive** zsh sessions. Comments work fine inside
scripts (`#!/bin/zsh` scripts have comments enabled).

### Impact

None on functionality — the Terraform commands on the following lines still
ran. It is noise only.

### Fix / Workaround

Run commands **one at a time**, or enable interactive comments:

```bash
setopt interactivecomments        # session-only
# or permanently:
echo "setopt interactivecomments" >> ~/.zshrc
```

Better habit when working interactively: paste/run one command per line
without `#` comment lines in the pasted block.

---

## Issue 2: AWS CLI — `InvalidClientTokenId`

### Symptom

```
aws sts get-caller-identity
aws: [ERROR]: An error occurred (InvalidClientTokenId) when calling the
GetCallerIdentity operation: The security token included in the request is invalid.
```

### Diagnosis steps

```bash
aws configure list
```

Output showed the CLI was using a key from the shared credentials file
(`~/.aws/credentials`), access key ending `OZQQ`, last modified Aug 30:

```
access_key : ****************OZQQ : shared-credentials-file
secret_key : ****************xYbc : shared-credentials-file
```

`ls -la ~/.aws/` confirmed a `credentials` file dated Aug 30 — no environment
variables (`AWS_ACCESS_KEY_ID` etc.) were overriding it.

### Root cause

`InvalidClientTokenId` means AWS STS rejected the access key ID itself —
it does **not** exist in the account it was presented to. Common causes:

- The IAM access key was **deleted** or **deactivated** in the AWS console.
- The key belongs to a **different AWS account** than the one intended.
- The key was a temporary/invalid value (typo, truncated copy).

It is *not* an expired-session issue (that gives `ExpiredToken`), and not a
permission issue (that gives `AccessDenied`).

### Fix

1. AWS Console → IAM → Users → (your user) → Security credentials.
2. Verify whether key `...OZQQ` still exists. If missing/inactive, create a
   new access key (purpose: CLI) and copy the Access Key ID + Secret.
3. Update local credentials:

```bash
aws configure
# AWS Access Key ID     : <new key>
# AWS Secret Access Key : <new secret>
# Default region        : us-east-1
# Default output        : json
```

Or non-interactively:

```bash
aws configure set aws_access_key_id <NEW_ACCESS_KEY_ID>
aws configure set aws_secret_access_key <NEW_SECRET_ACCESS_KEY>
aws configure set default.region us-east-1
aws configure set default.output json
```

4. Verify:

```bash
aws sts get-caller-identity
```

Expected: JSON with `UserId`, `Account`, `Arn`.

### Verified

After the new key was configured, `terraform init` succeeded — it was able
to configure the **S3 backend** and download modules/providers from the
registry, which requires valid AWS + network access.

---

## Issue 3: Terraform — `Unsupported argument` in EKS module (v20 → v21 breaking changes)

### Symptom

`terraform validate` / `plan` failed with 6 errors:

```
Error: Unsupported argument
  on eks.tf line 5, in module "eks":
   5:   cluster_name    = var.cluster_name
An argument named "cluster_name" is not expected here.
```

Same error for: `cluster_version`, `cluster_endpoint_public_access`,
`cluster_endpoint_private_access`, `cluster_encryption_config`,
`cluster_enabled_log_types`.

Because `plan` failed, no `tfplan` file was written, so `apply tfplan`
additionally failed with:

```
Error: Failed to load "tfplan" as a plan file
Error: stat tfplan: no such file or directory
```

### Root cause

`eks.tf` pinned the module with `version = "~> 21.0"`, so `terraform init`
downloaded **terraform-aws-modules/eks/aws v21.29.0**.

EKS module **v21 renamed/removed many top-level input variables** that existed
in v20. The configuration was still written in v20 syntax, so every renamed
argument was rejected as "Unsupported argument".

Confirmed by inspecting the downloaded module:

```bash
rg -n "^variable " .terraform/modules/eks/variables.tf
```

which showed the new names (`name`, `kubernetes_version`, `enabled_log_types`,
`endpoint_private_access`, `endpoint_public_access`, `encryption_config`).

### Mapping applied (v20 → v21)

| v20 argument (old, invalid)       | v21 argument (new, correct)         |
|-----------------------------------|-------------------------------------|
| `cluster_name`                    | `name`                              |
| `cluster_version`                 | `kubernetes_version`                |
| `cluster_endpoint_public_access`  | `endpoint_public_access`            |
| `cluster_endpoint_private_access` | `endpoint_private_access`           |
| `cluster_encryption_config`       | `encryption_config` (same shape)    |
| `cluster_enabled_log_types`       | `enabled_log_types`                 |

Unchanged in v21 (left as-is): `vpc_id`, `subnet_ids`, `enable_irsa`,
`authentication_mode`, `enable_cluster_creator_admin_permissions`,
`eks_managed_node_groups`, `tags`.

### Additional fix: KMS key ownership

v21 has `create_kms_key` (default `true`) — the module creates its **own**
KMS key for secrets encryption. This project already defines a key in
`kms.tf` (`aws_kms_key.eks` + alias). Without intervention, applying would
have created a **second, unused** KMS key.

Fix: set `create_kms_key = false` in the module and keep passing the
external key:

```hcl
create_kms_key = false

encryption_config = {
  provider_key_arn = aws_kms_key.eks.arn
  resources        = ["secrets"]
}
```

The module also auto-attaches the KMS encryption policy to the cluster IAM
role (`attach_encryption_policy` defaults to `true`), so the external key
still works.

### Changes made to `eks.tf`

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name          # was cluster_name
  kubernetes_version = var.cluster_version       # was cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access  = false                # was cluster_endpoint_public_access
  endpoint_private_access = true                 # was cluster_endpoint_private_access

  enable_irsa = true

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  create_kms_key = false                         # NEW — use kms.tf key

  encryption_config = {                          # was cluster_encryption_config
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
                                               # was cluster_enabled_log_types

  eks_managed_node_groups = { ... }              # unchanged
  tags = { ... }                                 # unchanged
}
```

### Verification

```bash
terraform validate
# Success! The configuration is valid.
```

### Next steps

```bash
terraform plan -out=tfplan     # run alone, wait for it to finish
terraform apply tfplan         # then apply the saved plan
```

---

## Issue 4: Mid-apply DNS outage — stale state lock, orphaned nodegroups, missing addons

### Symptom

`terraform apply` failed mid-run with a cascade of errors:

```
Error: Error acquiring the state lock
  ConditionalCheckFailedException: The conditional request failed
```

then, on retry:

```
Error: failed to upload state: ... dial tcp: lookup
my-enterprise-tf-state-bucket.s3.us-east-1.amazonaws.com: no such host

Error: failed to persist state to backend
  ... state has been written to the file "errored.tfstate"

Error: creating EKS Add-On (enterprise-eks:vpc-cni): ResourceInUseException:
Addon already exists.

Error: waiting for EKS Node Group (enterprise-eks:system-f20b45b602291efbf40fd06e1f)
create: ... dial tcp: lookup eks.us-east-1.amazonaws.com: no such host

Error: Error releasing the state lock
  ... lookup dynamodb.us-east-1.amazonaws.com: no such host
```

Post-apply state observed via kubectl/AWS CLI:

- Only `aws-node` (vpc-cni) pods running — **no CoreDNS, no kube-proxy**
- **4 nodegroups** in AWS (`system-ca44b...`, `system-f2f1a...`, `system-f4f0...`,
  `system-f20b...`) but Terraform tracked only one (tainted)
- One nodegroup unhealthy: `VcpuLimitExceeded` — account vCPU limit was 8
- `errored.tfstate` left in the working directory

### Diagnosis steps

```bash
nslookup eks.us-east-1.amazonaws.com        # resolved fine AFTER the outage
scutil --dns | head -30                     # resolver was the home router
                                            # (IPv6 address, via en0)
ps aux | grep -i terraform                  # check for live/stale processes
aws eks list-nodegroups --cluster-name enterprise-eks --region us-east-1
aws eks describe-addon --cluster-name enterprise-eks --addon-name coredns \
  --region us-east-1                        # ResourceNotFoundException
kubectl get nodes --show-labels             # nodes belonged to orphaned NGs
```

### Root cause

**Transient DNS failure from the local resolver** (router-provided IPv6 DNS)
mid-`apply`. Three consequences:

1. **State not uploaded** — S3 PutObject failed; Terraform wrote the newer
   state to local `errored.tfstate` (serial 11) while remote state was older.
2. **Lock not released** — DynamoDB unreachable, leaving stale locks that
   blocked every subsequent command with `ConditionalCheckFailedException`.
3. **Nodegroup tainted** — EKS API polling failed mid-create, so Terraform
   marked `system-f20b...` as tainted and must replace it. Earlier interrupted
   applies had already created orphaned nodegroups not recorded in state.
   Each retry created another orphan until the account hit its **8-vCPU
   limit**, causing `VcpuLimitExceeded` on subsequent launches.

`coredns` and `kube-proxy` addons were never created because the apply died
before reaching them — hence no cluster DNS and missing system pods.

### Resolution

1. **Cleared stale locks** (verified no terraform process was running first):

   ```bash
   terraform force-unlock <lock-id-from-error>
   ```

2. **Fixed DNS** to stop recurrence (router resolver was unreliable):

   ```bash
   networksetup -setdnsservers Wi-Fi 8.8.8.8 1.1.1.1
   # revert later with:
   # networksetup -setdnsservers Wi-Fi Empty
   ```

3. **Pushed the newer local state** so Terraform knew about partially-created
   resources (also resolved the vpc-cni `ResourceInUseException` 409):

   ```bash
   terraform state push errored.tfstate
   ```

4. **Deleted the 3 orphaned nodegroups** not in Terraform state — this also
   freed the 8 vCPUs needed for the replacement nodegroup:

   ```bash
   aws eks delete-nodegroup --cluster-name enterprise-eks \
     --nodegroup-name system-ca44b46bc2fd768a2f2aff8244 --region us-east-1
   aws eks delete-nodegroup --cluster-name enterprise-eks \
     --nodegroup-name system-f2f1a21fd68de99345feaa8ecb --region us-east-1
   aws eks delete-nodegroup --cluster-name enterprise-eks \
     --nodegroup-name system-f4f00c4fce96c016e6d12d9941 --region us-east-1
   ```

5. **Ran `terraform apply`** — replaced the tainted nodegroup and created the
   missing `coredns` + `kube-proxy` addons.

### Verification

```bash
aws eks list-nodegroups --cluster-name enterprise-eks --region us-east-1
# system-574425f652fa5c8260c8235c2b     (single nodegroup, ACTIVE, desired=2)

kubectl get nodes
# 2/2 Ready

kubectl get pods -A
# coredns (2), kube-proxy (2), aws-node (2) — all Running
```

### Lessons learned

- **Never force-unlock while an apply may be running** — check `ps aux | grep
  terraform` first; a lock with a fresh `Created` timestamp usually means a
  live process, not a stale lock.
- **Finish or kill interrupted applies before retrying** — every partial
  apply created another orphaned nodegroup.
- The account's **8-vCPU limit** caps capacity at 4× m6i.large (or 2 with a
  replacement racing deletions) — request a limit increase before scaling.
- Delete `errored.tfstate` after successful recovery — it contains cluster
  certificates/secrets and must not be committed.

---

## Environment summary (known-good state at end of session)

| Tool     | Version  | Notes                                  |
|----------|----------|----------------------------------------|
| Terraform| v1.14.3  | latest is 1.16.6 — optional upgrade    |
| aws-cli  | 2.36.30  | credentials verified via STS          |
| kubectl  | v1.35.0  | connected; cluster healthy (2 nodes)   |
| EKS mod  | v21.29.0 | v21 syntax applied                     |
| VPC mod  | v6.7.3   | `~> 6.0`, no issues                    |
