# Vercel DNS as code (Terraform, HCP VCS-Driven)

Declarative management of DNS records on Vercel. Terraform code lives here; **plan
and apply run on HCP Terraform** (Remote execution, VCS-Driven workflow). No
Terraform / Vercel secrets in GitHub — they live inside the HCP workspace.

## Files

- [providers.tf](providers.tf) — Terraform + Vercel provider versions, HCP cloud backend.
- [dns.tf](dns.tf) — the only file you normally edit. Records live in `local.dns_records`.

## Architecture

```
┌─────────────┐  git push / PR   ┌────────────────────┐   Vercel API
│  GitHub     │ ───────────────► │  HCP Terraform     │ ──────────────► Vercel DNS
│  (source)   │  via HCP GitHub  │  (remote plan/     │
│             │  App webhook     │   apply + state)   │
└─────────────┘                  └────────────────────┘
```

- PR → HCP speculative plan, posted back as a PR check.
- merge `main` → HCP queues a plan; you click **Confirm & Apply** (auto-apply off
  by default).

## One-time setup

1. **HCP Terraform workspace** (organization `brickverse`)
   1. Account Settings → Tokens → **Create a GitHub App token** → authorize the
      HashiCorp GitHub App on `Jeff-Tian/my-body`.
   2. Org Settings → Version Control → Providers → confirm the GitHub connection
      exists.
   3. Create / edit workspace **`my-body-dns`**:
      - **Workflow**: Version Control Workflow
      - **Repository**: `Jeff-Tian/my-body`
      - **Terraform Working Directory**: `infra/terraform`
      - **VCS branch**: `main`
      - **Auto-apply**: off
      - **Execution Mode**: **Remote**

2. **Vercel token inside HCP workspace** (workspace → Variables):

   | Key                | Value                                 | Category              | Sensitive |
   |--------------------|---------------------------------------|-----------------------|-----------|
   | `VERCEL_API_TOKEN` | <https://vercel.com/account/tokens>   | Environment variable  | ✅         |
   | `VERCEL_TEAM_ID`   | team id (optional)                    | Environment variable  | ❌         |

   The Vercel provider auto-reads these env vars — no `TF_VAR_` prefix needed.

3. **Import the existing `mybody` CNAME** (created earlier via the dashboard).
   Do this once from your laptop; state then lives on HCP forever.

   ```sh
   cd infra/terraform
   set -a; source ../../.env; set +a   # local Vercel creds for the import call

   terraform login            # first time only; stores ~/.terraform.d/credentials.tfrc.json
   terraform init

   # Look up the record id on Vercel:
   curl -s -H "Authorization: Bearer $VERCEL_API_TOKEN" \
     "https://api.vercel.com/v4/domains/hardway.app/records${VERCEL_TEAM_ID:+?teamId=$VERCEL_TEAM_ID}" \
     | jq '.records[] | select(.name=="mybody" and .type=="CNAME")'

   # Import (replace <record_id>):
   terraform import 'vercel_dns_record.records["mybody_cname"]' <record_id>
   ```

   If no record exists yet, skip the import — the first apply will create it.

## Day-to-day workflow

1. Edit `local.dns_records` in [dns.tf](dns.tf).
2. Open a PR → HCP posts a speculative plan as a PR check.
3. Merge to `main` → HCP queues a plan → click **Confirm & Apply** on HCP.

Removing an entry deletes the DNS record on next apply. Manual edits in the Vercel
dashboard are drift and will be reverted.

## Local dry run (optional)

```sh
cd infra/terraform
set -a; source ../../.env; set +a
terraform init
terraform plan     # runs remotely on HCP; output streams back to your terminal
```
