# Creates a Vaultwarden Container App with Azure File & PostgreSQL Storage

[![Deploy to Azure (ARM JSON)](
https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true
)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBernd-Schneider-Software-Engineering%2Fazure-aca-vaultwarden%2Fmaster%2Fmain.json
)


[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](
http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2FVertax1337%2Fvaultwarden-azure%2Fmaster%2Fmain.json
)

---
## Endkunden-Dokumentation
- [Vaultwarden – How to Use (BSSE)](./docs/HowToUse/HowToUse.pdf)
- [Vaultwarden – How to Use (BSSE) PDF-VERSION ](./docs/HowToUse/HowToUse.pdf)

## Overview

This template deploys **Vaultwarden** as an **Azure Container App (Consumption)** with:

- Persistent **Azure File Share** storage (`/data`)
- **PostgreSQL Flexible Server** backend
- Built-in **SMTP support** (Microsoft 365 compatible)
- Designed for **KMU / small enterprise production usage**
- Cost-efficient (no App Service Plan, no Front Door / WAF required)

The deployment supports **backup & restore** scenarios and **safe container updates** without data loss.

---
## Azure Files Backup (IaC)

Dieses Template kann **Azure Backup für Azure Files** für das Vaultwarden-`/data`-Share automatisch aktivieren.
Dabei werden erstellt:

- **Recovery Services Vault**
- **Backup Policy** (AzureFileShare)
- **Protection Container** + **Protected Item** für das File Share

**Parameter (Defaults):**
- `azureFilesBackupEnabled`: `true`
- `azureFilesBackupScheduleRunTime`: `05:30` (HH:MM, Minuten 00 oder 30)
- `azureFilesBackupTimeZone`: `UTC`
- `azureFilesBackupDailyRetentionDays`: `30`
- `azureFilesBackupWeeklyDaysOfWeek`: `Sunday, Tuesday, Thursday`
- `azureFilesBackupWeeklyRetentionWeeks`: `12`

Doku-Referenz: [Microsoft Learn Quickstart – Configure vaulted backup for Azure Files using ARM](https://learn.microsoft.com/en-us/azure/backup/quick-backup-azure-files-vault-tier-arm).

---


## SMTP Modus: Direct Send (Default) vs. SMTP Auth

Das Template unterstützt zwei Betriebsarten:

### A) Direct Send (Default, **nur intern** im Microsoft 365 Tenant)

- **Default:** `smtpUseAuth = false`
- Es werden **keine** Env-Variablen/Secrets für `SMTP_USERNAME`, `SMTP_PASSWORD` oder `SMTP_AUTH_MECHANISM` angelegt.
- `SMTP_HOST` wird **automatisch** via **MX-Lookup** ermittelt – basierend auf der Domain aus `domainUrl`.
- `SMTP_FROM` wird automatisch auf `vault@kundendomain.tld` gesetzt (ebenfalls aus `domainUrl` abgeleitet).

**Wichtig (Ableitung der Domain):**  
Aus `domainUrl` wird der Hostname extrahiert (z. B. `vault.kunde.tld`) und als **Base-Domain** standardmäßig die letzten **2 Labels** verwendet (→ `kunde.tld`).  
Falls du exotische Public-Suffixes hast (z. B. `co.uk`) oder bewusst eine andere Mail-Domain brauchst, setze **manuell**:
- `smtpHost` (Override des SMTP Hosts, statt MX-Lookup)
- `smtpFrom` (Override der Absenderadresse)

**Hinweis:** Direct Send ist für **interne Empfänger** gedacht (User/Postfächer/Shared Mailboxes im gleichen Tenant).
Wenn du an **externe** Empfänger senden willst oder SMTP Auth erzwingen musst, nutze Modus B.

### B) SMTP Auth (optional, auch für extern)

- `smtpUseAuth = true`
- `SMTP_HOST`: Default `smtp.office365.com` (kann über `smtpHost` überschrieben werden)
- `smtpPort`: Default `587`
- `smtpUsername` + `smtpPassword` sind Pflicht
- Optional: `smtpAuthMechanism`, `smtpFromName`, `heloName`

---

## Manueller Schritt (Direct Send): Absender-Adresse/Shared Mailbox

Die Anlage eines (freigegebenen) Postfachs wird **nicht** automatisch im Deployment gemacht (bewusst: Tenant-Admin-Rechte, Governance, Trennung IaC/Identity).

Empfehlung: Lege ein freigegebenes Postfach an, z. B. `vault@kundendomain.tld`, und nutze dieses als Absender.

Beispiel (Exchange Online PowerShell):

```powershell
New-Mailbox -Shared -Name "Vaultwarden" -Alias "vault" -PrimarySmtpAddress "vault@kundendomain.tld"
```

---

## Deployment


### 1. Click **Deploy to Azure**
You can choose between:
- **ARM JSON** (portal-friendly, classic)
- **Bicep** (recommended for technical users & CI/CD)

### Optional: Local deployment (PowerShell)
If you prefer a scripted deployment (e.g., for repeatability), use:

```powershell
./scripts/deploy.ps1 -ResourceGroupName <RG-NAME> -Environment prod \
  -DomainUrl https://vault.example.com \
  -SmtpUseAuth:$false \
```

> Tip: `./deploy.ps1` exists as a small forwarder and simply calls `./scripts/deploy.ps1`.

### 2. Fill in the parameters

- **Resource Group**  
  All resources will be created inside this group.

- **Environment (Tag / Kostenübersicht)**  
  Default: `prod` (allowed: `prod`, `test`, `dev`).  
  Wird als Tag `Environment` auf die Ressourcen geschrieben, damit Azure Cost Management sauber filtern kann.

- **BSSE Deploy Ref (Tag / Traceability)**  
  Wird als Tag `bsse:ref` gesetzt, um nachzuvollziehen, welcher Stand deployed wurde.

  **Automatisch (ohne manuelle Eingabe):**  
  Wenn `bsseRef` **leer** bleibt, versucht das Template den Ref aus der **Template-URL** des Deployments zu ermitteln (z. B. `main` / `master` / `v1.2.3`), sofern du über einen GitHub/Raw-Link deployest (Deploy-to-Azure Button / Template-Link).  
  Bei lokalen Deployments ohne Template-Link wird als Fallback `local` gesetzt.

  **Präzise (empfohlen für echte Traceability):**  
  Wenn du einen **Commit-SHA** oder einen **Release-Tag** in `bsseRef` übergibst, landet genau dieser Wert in `bsse:ref`.

- **Storage Account Type**  
  Default: `Standard_LRS`  
  For higher resilience you may choose `Standard_GRS`, `ZRS`, etc.

- **Admin API Token (`/admin`)**
  - Wird beim Deployment automatisch erzeugt und im **Azure Key Vault** gespeichert
  - Wird der Container App als Secret (Key Vault Reference) bereitgestellt

- **Key Vault Name (Soft-Delete safe)**

  The Key Vault name is auto-generated with a short random suffix to avoid name collisions with
  Key Vaults that are still in the **soft-deleted** state.
  The effective name is shown in the deployment output `keyVaultName`.

- **CPU / Memory sizing**  
  Recommended starting point:
  - `0.25 CPU`
  - `0.5 GiB RAM`

  Valid combinations:

  | CPU  | Memory |
  |-----:|-------:|
  | 0.25 | 0.5 Gi |
  | 0.5  | 1.0 Gi |
  | 0.75 | 1.5 Gi |
  | 1.0  | 2.0 Gi |
  | 1.25 | 2.5 Gi |
  | 1.5  | 3.0 Gi |
  | 1.75 | 3.5 Gi |
  | 2.0  | 4.0 Gi |

 - **Database admin password**

  The PostgreSQL **admin password is auto-generated** during deployment and **not stored** in Key Vault.
  For day-to-day operations Vaultwarden uses a separate **least-privilege database user**.
  If you ever need admin access, reset the admin password in Azure (Portal/CLI) and connect with the new value.

- **TLS Hinweis (PostgreSQL / `DATABASE_URL`)**  
  `DATABASE_URL` wird mit `sslmode=require` erzeugt (Transportverschlüsselung aktiv).  
  Hinweis: `require` erzwingt TLS, prüft aber i. d. R. **nicht** strikt das Server-Zertifikat. Wenn ihr striktere Zertifikatsprüfung wollt (z. B. `verify-full`/CA), muss das Trust-Store/CA-Handling im Container mitgedacht werden.

---

### 3. Deploy

Click **Deploy**.

> ⚠️ **Known Azure timing issue**  
> In rare cases the Container App may fail on first deployment because the Azure File share is not yet linked.
>
> **Fix:** Click **Redeploy** and reuse the same parameters.  
> No data will be lost.

---

## Post-Deployment Steps (Required for Production)

1. **Configure Custom Domain**
   - ⚠️ **IMPORTANT: THE CONTAINER APP MUST BE RUN TO OBTAIN A MANAGED CERTIFICATE !!!!!**
   - Add the required CNAME / TXT records shown in the Azure Portal

3. **Enable Managed Certificate**
   - Azure issues the TLS certificate after DNS verification

4. **Disable HTTP**
   - Set parameter `allowInsecureHttp = false`
   - Enforces HTTPS-only access
     
5. **Microsoft Edge Konfiguration: Enhanced Security Mode (Bypass-Liste)**

     Um einen reibungslosen Zugriff auf interne Ressourcen zu gewährleisten und gleichzeitig die Browsersicherheit zu maximieren, wurde im Microsoft Intune Admin Center eine spezifische Richtlinie für Windows-Geräte konfiguriert. 

     Konfigurationsdetails:
     Richtlinien-Name: W10 - Browser - HardeningException
     Plattform: Windows
     Zuweisung: Alle Firmengeräte (Eingeschlossene Gruppen: All devices, All users)

     Wichtige Einstellung:
     In den Configuration settings unter der Kategorie Microsoft Edge sind folgende Optionenen zu aktivieren:

     Einstellung:
     Configure the list of domains for which enhance security mode will not be enforced
     (Konfiguriere die Liste der Domänen, für die der erweiterte Sicherheitsmodus nicht erzwungen wird).
     **Status: Aktiviert (Enabled)**
   
     Ausgenommene Domäne:
     **vault.firma.tld**
   
     Hinweis: Diese Einstellung MUSS gesetzt sein, da der Browser ansonsten im Sicherheitsmodus die Registrierung auf den Vault blockieren und dessen Funktionen eingeschränkt sind.
---

## Updating Vaultwarden

By default the deployment pins a specific Vaultwarden image version (see the `vaultwardenImage` parameter).
To update Vaultwarden, create a new revision and set the image tag to the desired version.

1. Azure Portal → Resource Group → **vaultwarden**
2. **Revisions**
3. **Create revision**
4. Set the image tag to the desired Vaultwarden version (e.g. `vaultwarden/server:1.35.2-alpine`)
5. Create revision

✔ No downtime  
✔ Persistent data remains intact  
✔ Database migrations are handled automatically

> Tip: Keep the template parameter `vaultwardenImage` aligned with your preferred version for fresh deployments.

---

## Get Admin Token

1. Azure Portal → Resource Group → **vaultwarden**
2. Container App → **Configuration**
3. Environment Variables
4. Copy the value of `ADMIN_TOKEN`

Admin UI:
```
https://<your-domain>/admin
```

---

## Notes

- SMTP is **mandatory** for:
  - Password reset
  - Signup verification
  - Security notifications
- Microsoft 365 SMTP (`smtp.office365.com`) is fully supported
- Secrets are stored as **Container App Secrets**
- Azure Container Apps (Consumption) keeps costs low while remaining production-ready
