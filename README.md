# Email intake agent

A .NET 10 Razor Pages application for Azure App Service that invokes **Azure AI Foundry agents** to understand email bodies and attached forms/documents, categorize them, and recommend follow-up actions.

Based on the [invoice-ledger application](https://github.com/qkfang/invoice-ledger-agent/tree/main/src/invledger_app) and the [client-iq Work IQ integration](https://github.com/qkfang/client-iq-agent/tree/main/src/web).

## What it does

- Paste an email subject, sender and body, and upload up to five attachments.
- Extract layout, tables and form content with Azure AI Document Intelligence `prebuilt-layout`; TXT/CSV are read as UTF-8.
- Invoke a named Foundry agent through the Responses API with the email and extracted document evidence.
- Display category, confidence, summary, document fields/missing fields, citations, warnings and suggested action.
- Alternatively, use the **Work IQ** panel to find one Microsoft 365 email in the signed-in user's context and analyze available body/attachment evidence.
- Flag uncertain, unreadable, truncated or incomplete evidence for human review.

Categories: Invoice, PurchaseOrder, Application, Support, Compliance, General and Unknown.

This is **read-only triage**, not a mailbox listener. It does not automatically poll incoming mail or apply Outlook categories, move messages, send replies, or execute suggested actions. Work IQ may return snippets or attachment metadata rather than document bytes; upload the original attachments for full extraction. There is no fabricated/local AI fallback.

## Architecture

Browser → authenticated Razor Pages → Document Intelligence (uploaded bytes) → Foundry email-intake agent → rendered result.

For Microsoft 365: Entra sign-in → delegated Foundry token → Foundry agent with native `work_iq_preview` tool → existing OAuth Work IQ project connection.

The upload agent has **no tools**. The Work IQ agent has only the hosted Work IQ tool, not a public application MCP callback. Each variant's agent version is created lazily with the app identity and invoked using that exact version. Uploaded emails use managed identity (developer credentials locally); Work IQ uses the signed-in user's Foundry credential. Uploaded evidence never enters the Work IQ-enabled agent.

Repository files:

- `/home/runner/work/email-intake-agent/email-intake-agent/src/EmailIntake.Web`: web application.
- `/home/runner/work/email-intake-agent/email-intake-agent/infra/main.bicep`: resource-group deployment.
- `/home/runner/work/email-intake-agent/email-intake-agent/infra/main.bicepparam`: safe sample parameters.
- `/home/runner/work/email-intake-agent/email-intake-agent/EmailIntake.slnx`: solution.

Commands below use this checkout's absolute path; change `ROOT` for a different checkout.

## Run locally

Prerequisites: .NET 10 SDK, Azure CLI, a Foundry project with a chat model deployment, and Document Intelligence for PDF/image/Office attachments.

```bash
ROOT=/home/runner/work/email-intake-agent/email-intake-agent
APP="$ROOT/src/EmailIntake.Web"
az login
dotnet user-secrets set --project "$APP" "Foundry:ProjectEndpoint" "https://YOUR-ACCOUNT.services.ai.azure.com/api/projects/YOUR-PROJECT"
dotnet user-secrets set --project "$APP" "Foundry:ModelDeploymentName" "gpt-4.1"
dotnet user-secrets set --project "$APP" "DocumentIntelligence:Endpoint" "https://YOUR-DOC-ACCOUNT.cognitiveservices.azure.com/"
dotnet build "$ROOT/EmailIntake.slnx"
dotnet run --project "$APP" --launch-profile https
```

Use the HTTPS URL printed by `dotnet run`. For upload-only development, Entra settings can be empty. Without Azure configuration the UI still loads, but processing shows a configuration error. Authentication is **mandatory outside Development**; the app refuses to start without `AzureAd:ClientId`. Do not expose the unauthenticated Development environment publicly.

Grant your local Azure identity **Azure AI User** on the Foundry account and **Cognitive Services User** on Document Intelligence. A model deployment with sufficient quota must exist. Azure role changes may take several minutes to propagate.

Configuration can also be supplied as environment variables; replace `:` with `__`.

| Setting | Purpose |
| --- | --- |
| `Foundry:ProjectEndpoint` | Foundry project endpoint, not just the account endpoint |
| `Foundry:ModelDeploymentName` | Chat deployment name, default `gpt-4.1` |
| `Foundry:AgentName` | Base agent name, default `email-intake` |
| `DocumentIntelligence:Endpoint` | Document Intelligence custom-subdomain endpoint |
| `Foundry:WorkIqConnectionId` | Full resource ID of a consented OAuth Work IQ connection in the configured project |
| `AzureAd:Instance` | `https://login.microsoftonline.com/` |
| `AzureAd:TenantId` | Entra tenant GUID |
| `AzureAd:ClientId` | Web application registration GUID |
| `AzureAd:ClientSecret` | User secret locally; Key Vault reference on App Service |
| `AzureAd:CallbackPath` | `/signin-oidc` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Enables request/dependency/trace telemetry |

Never place client secrets or access tokens in source files or Bicep parameter files.

## Work IQ and Entra setup

1. Register a **single-tenant Entra web application**. Add a Web redirect URI `https://YOUR-WEB-APP.azurewebsites.net/signin-oidc` and your local HTTPS origin plus `/signin-oidc` if developing locally. Configure `/signout-callback-oidc` as the front-channel logout URL where required.
2. Configure the delegated Foundry API permission for scope **`https://ai.azure.com/.default`** (the underlying delegated permission is `user_impersonation`) and grant tenant consent as required. The reference application's direct Work IQ A2A scope is different and is **not** the scope used by this app.
3. Create a client credential. Store it with .NET user secrets locally or in an existing Key Vault for App Service. Grant the Web App managed identity secret-read access to that vault.
4. In the configured Foundry project, create the **OAuth Work IQ connection** for the native Work IQ preview tool. Complete the tenant/provider authorization and user consent required by that connection. Set `Foundry:WorkIqConnectionId` to its full resource ID. The tool uses `https://workiq.svc.cloud.microsoft/mcp` and `type: work_iq_preview`, matching client-iq.
5. Give participating users **Azure AI User** on the Foundry account/project as appropriate for agent invocation. Their Microsoft 365 permissions and tenant's Work IQ availability/licensing still apply.
6. Configure `AzureAd` settings, sign in, and use a specific search such as “Find the latest incoming email about an invoice from Contoso.”

Bicep cannot register this Entra application or complete interactive Work IQ consent. Managed identity alone is **not** a substitute for delegated Work IQ access. This integration uses preview Foundry packages and native Work IQ availability depends on the tenant/project/region. Approval-required tool calls are surfaced as errors rather than blanket auto-approved.

## Deploy Azure resources

The Bicep deployment provisions:

- Linux App Service plan/Web App (`DOTNETCORE|10.0`) with system-assigned managed identity, HTTPS/TLS 1.2, disabled FTP/SCM basic publishing credentials.
- Foundry AIServices account, project and configurable chat deployment.
- Document Intelligence account with key-based authentication disabled.
- Log Analytics and Application Insights.
- Scoped Azure AI User and Cognitive Services User role assignments for the Web App.
- Account-scoped Azure AI User for the Foundry project identity, so agent-side model inference works when provisioned through Bicep.
- App settings for endpoints, model, Entra, Work IQ and telemetry; optional Entra secret **Key Vault reference**.

Model/region availability and quota are subscription-specific. Review `aiLocation`, model name/version, deployment SKU and capacity before deployment. This template creates a new Foundry project; create its Work IQ connection afterward, then redeploy with the connection ID.

```bash
ROOT=/home/runner/work/email-intake-agent/email-intake-agent
az login
az account set --subscription YOUR-SUBSCRIPTION-ID
az group create --name email-intake-rg --location eastus2
az deployment group create \
  --resource-group email-intake-rg \
  --name email-intake \
  --template-file "$ROOT/infra/main.bicep" \
  --parameters "$ROOT/infra/main.bicepparam" \
  --parameters azureAdClientId=YOUR-CLIENT-ID \
               azureAdClientSecretUri=https://YOUR-VAULT.vault.azure.net/secrets/YOUR-SECRET
```

Read the deployment outputs for the Web App URL/name, Foundry project endpoint/resource ID, Document Intelligence endpoint and managed identity principal ID. Add the actual Web App redirect URI to Entra and grant the Key Vault role before starting the application. For an RBAC-enabled vault, assign **Key Vault Secrets User** to the Web App principal at the intended vault scope. Keep the vault accessible to App Service through your chosen network configuration.

Once the OAuth connection exists, repeat the deployment with `foundryWorkIqConnectionId=YOUR-FULL-CONNECTION-RESOURCE-ID`.

## Deploy application code

Use Azure CLI's Entra-authenticated ZIP deployment; basic publishing credentials remain disabled.

```bash
ROOT=/home/runner/work/email-intake-agent/email-intake-agent
dotnet publish "$ROOT/src/EmailIntake.Web" --configuration Release --output /tmp/email-intake-publish
(cd /tmp/email-intake-publish && zip -r /tmp/email-intake.zip .)
az webapp deploy --resource-group email-intake-rg --name YOUR-WEB-APP-NAME \
  --src-path /tmp/email-intake.zip --type zip
```

Verify `/health` returns `{"status":"healthy"}`, sign in at `/`, and try an email and attachment. The health endpoint checks HTTP liveness only, not Azure service readiness. Confirm Document Intelligence extraction, Foundry output, Work IQ user context and tenant isolation in your own subscription.

## Validation and operations

```bash
ROOT=/home/runner/work/email-intake-agent/email-intake-agent
dotnet build "$ROOT/EmailIntake.slnx" --configuration Release
dotnet format "$ROOT/EmailIntake.slnx" --verify-no-changes --no-restore
dotnet list "$ROOT/EmailIntake.slnx" package --vulnerable --include-transitive
az bicep build --file "$ROOT/infra/main.bicep" --outfile /tmp/email-intake-template.json
az bicep build-params --file "$ROOT/infra/main.bicepparam" --outfile /tmp/email-intake-parameters.json
```

There is no automated test suite yet. Manual smoke checks: missing configuration, blank/oversized inputs, unsupported/empty/oversized attachments, missing anti-forgery token, disabled Work IQ without sign-in, and production startup without Entra configuration.

Limits: five files, 10 MB each, 20 MB total; body 50,000 characters; extracted text 60,000 characters per attachment; three-minute processing timeout; two concurrent requests per signed-in user/IP per instance. Supported uploads: PDF, PNG/JPEG/TIFF/BMP, DOCX/XLSX/PPTX and UTF-8 TXT/CSV. Unsupported or failed extraction is not silently treated as successful analysis. Files must be reselected after validation errors.

Email, attachment content and AI output are treated as untrusted; Razor HTML-encodes output and forms use anti-forgery validation. No public document URLs or write-capable MCP endpoints are exposed. Prompt instructions alone cannot guarantee immunity to prompt injection, so retain human review and least-privilege service connections.

Email/result data is not persisted in an application database, but ASP.NET may buffer multipart uploads temporarily on disk, and Azure AI services may retain input/output according to service policies. Logs intentionally exclude email content and tokens. Review Azure retention, telemetry and tenant policy before processing sensitive information.

The app uses an in-memory token cache and per-instance agent-version cache. For production scale-out, configure a shared encrypted token cache, persistent ASP.NET Data Protection keys, shared rate limiting, retention/auditing controls and any required private networking. Cached tokens and sessions can be lost on restart. Agent versions accumulate on cold starts; manage their lifecycle in Foundry. This repository does not provision these additional production facilities.