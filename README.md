# Azure Terraform CI/CD with GitHub Actions

A working deployment pipeline: **plan on pull request, apply on merge**, authenticating to Azure with **OIDC federated credentials** (no stored secret) and gated by a **required approval** before anything changes.

Built as a lab. Small enough to cost near nothing, real enough to talk about.

---

## What this demonstrates

| Capability | Where it shows |
|---|---|
| CI/CD pipeline construction | `.github/workflows/terraform.yml` — two jobs, PR-triggered plan and merge-triggered apply |
| Infrastructure as Code | `main.tf` — resource group, virtual network, subnet, NSG, storage account |
| Remote state with locking | Azure Storage backend; blob lease locking is native, no DynamoDB equivalent needed |
| Secretless authentication | Workload identity federation — GitHub's OIDC token exchanged for an Azure token at run time |
| Change control in a pipeline | GitHub Environment with a required reviewer standing between plan and apply |
| Plan visibility | Terraform plan posted back to the pull request as a comment |

**The interview sentence:** *"I built a GitHub Actions pipeline that plans on pull request and applies on merge, authenticating to Azure through OIDC federation rather than a stored credential, with an approval gate before apply."*

Say it's a lab if asked. Built beats read about.

---

## Why OIDC instead of a service principal secret

The common pattern is to create a service principal, generate a client secret, and paste it into GitHub Secrets. That secret is a long-lived credential sitting in a third-party system, and it expires on a schedule somebody has to remember.

Workload identity federation removes it. GitHub Actions issues a short-lived OIDC token describing the workflow run — which repository, which branch, which environment. Azure is configured to trust tokens matching a specific subject, and exchanges them for an access token valid for that run only.

Nothing to rotate. Nothing to leak. And the trust is scoped to a named branch or environment, so a fork or a feature branch can't get a token.

This is the part worth explaining in an interview. It's a security answer inside a DevOps question, which is your angle rather than a generic candidate's.

---

## Azure setup

Run once. Replace the placeholder values.

### 1. State storage

```bash
az group create --name rg-tfstate --location centralus

az storage account create \
  --name sttfstategbyrd \
  --resource-group rg-tfstate \
  --location centralus \
  --sku Standard_LRS \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2

az storage container create \
  --name tfstate \
  --account-name sttfstategbyrd \
  --auth-mode login
```

Storage account names are globally unique, lowercase, no hyphens. Change it if that one is taken.

### 2. App registration for the pipeline

```bash
az ad app create --display-name "github-actions-terraform"
# note the appId that comes back

az ad sp create --id <APP_ID>
```

### 3. Federated credentials

One per trigger you want to allow. `OWNER/REPO` is your GitHub path.

```bash
# pull requests -> plan only
az ad app federated-credential create --id <APP_ID> --parameters '{
  "name": "github-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:OWNER/REPO:pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'

# the production environment -> apply
az ad app federated-credential create --id <APP_ID> --parameters '{
  "name": "github-env-production",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:OWNER/REPO:environment:production",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

The `subject` is the whole security control. Azure will only issue a token for a run matching it exactly.

### 4. Permissions

```bash
# deploy resources
az role assignment create \
  --assignee <APP_ID> \
  --role Contributor \
  --scope /subscriptions/<SUBSCRIPTION_ID>

# read and write state
az role assignment create \
  --assignee <APP_ID> \
  --role "Storage Blob Data Contributor" \
  --scope /subscriptions/<SUBSCRIPTION_ID>/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/sttfstategbyrd
```

Contributor at subscription scope is broad. Scoping it to a single resource group is the better habit and worth mentioning as a real-world adjustment — this is a lab, so breadth keeps it simple.

---

## GitHub setup

### Repository variables
*Settings → Secrets and variables → Actions → Variables*

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | the app registration's appId |
| `AZURE_TENANT_ID` | your tenant id |
| `AZURE_SUBSCRIPTION_ID` | your subscription id |
| `TFSTATE_RG` | `rg-tfstate` |
| `TFSTATE_SA` | `sttfstategbyrd` |
| `TFSTATE_CONTAINER` | `tfstate` |

Variables, not secrets — none of these are sensitive, and that's the point.

### Environment
*Settings → Environments → New environment → `production`*

Add yourself under **Required reviewers**. That's the approval gate: the apply job pauses until someone clicks through.

---

## Running it

1. Push this to a new repository, `main` branch.
2. Create a branch, change something in `main.tf`, open a pull request.
3. The plan job runs and comments the plan on the PR.
4. Merge. The apply job queues and waits for your approval.
5. Approve. It applies.

Then break it on purpose — a bad resource name, a wrong subject in the federated credential — and read the failure. That's where the understanding comes from, and it's what gets you through a follow-up question.

---

## What to add if you want more

- `terraform fmt -check` failing the build on unformatted code *(already in)*
- **tflint** or **checkov** as a policy gate before plan
- A second environment (`dev`) that applies without approval, so you can talk about differentiated controls per environment
- Drift detection: a scheduled workflow running `plan` nightly and opening an issue if state has moved

The drift detection one is worth doing. It's the piece most people skip and the one an operations-minded interviewer notices.
