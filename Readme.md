# Vaultwarden auf Azure Container Apps (ACA) – mit Azure Files + PostgreSQL

[![Deploy to Azure (ARM JSON)](
https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true
)](
https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FBernd-Schneider-Software-Engineering%2Fazure-aca-vaultwarden%2Fmaster%2Fmain.json
)

---

## Endkunden-Dokumentation
- [Vaultwarden – How to Use (BSSE)](./docs/HowToUse/HowToUse.pdf)

---

## Was dieses Template deployt

Dieses ARM-Template (`main.json`) deployt **Vaultwarden** als **Azure Container App (Consumption)** inkl. persistenter Datenhaltung und „Production-Grundausstattung“.

### Kern-Ressourcen (immer)
- **Azure Container Apps Environment** (mit Log Analytics)
- **Azure Container App** (Vaultwarden Container, Ingress extern, HTTPS-only per Default)
- **Azure Storage Account + Azure Files Share** (Mount nach `/data`)
- **Azure Database for PostgreSQL – Flexible Server** + **Datenbank**
- **User Assigned Managed Identity**
- **Azure Key Vault (RBAC)** für Secrets
- **Deployment Script** (Bootstrap):
  - erzeugt `ADMIN_TOKEN` und schreibt es in Key Vault
  - erzeugt DB-App-User (Least-Privilege) und schreibt `DATABASE_URL` in Key Vault
  - legt SMTP-Passwort als Secret ab (nur wenn SMTP Auth aktiv ist)
  - ermittelt bei *Direct Send* den SMTP Host per **MX-Lookup** (Output)

### Optional (per Parameter)
- **Azure Backup für Azure Files** (`azureFilesBackupEnabled=true`, Default: **true**)  
  Erstellt Recovery Services Vault + Backup Policy + Protection des File Shares.
- **Azure Communication Services Email (ACS SMTP)** (`smtpUseAuth=true` + `smtpAuthPreset=acsSmtp`)  
  Erstellt Email Service + Domain + Sender Username + Communication Service + SMTP Username + RBAC.

---

## SMTP: Betriebsarten

> Hinweis: Für SPF/DKIM/DMARC ist bei „direkt per SMTP aus der App senden“ die **Outbound/Egress-IP** relevant. Ohne statische Egress-IP ist *Direct Send* aus Azure heraus oft unzuverlässig.

### A) Direct Send (Default, nur intern im Microsoft 365 Tenant)
- Default: `smtpUseAuth = false`
- `SMTP_HOST` wird automatisch via **MX-Lookup** ermittelt (aus `domainUrl` → Base-Domain)
- `SMTP_FROM` wird automatisch gesetzt: `vault@<kundendomain.tld>` (override per Parameter möglich)
- Keine Secrets für `SMTP_USERNAME` / `SMTP_PASSWORD`

> Für externe Empfänger / saubere Zustellbarkeit: nutze SMTP Auth oder ACS SMTP.

### B) SMTP Auth (klassisch, z. B. M365 / eigener SMTP)
- `smtpUseAuth = true`
- Default Host (wenn `smtpHost` leer): `smtp.office365.com`
- Default Port: `587`
- Default Security: `starttls`
- `smtpUsername` + `smtpPassword` erforderlich

### C) ACS SMTP (Azure Communication Services Email) ✅ empfohlen
Wenn Direct Send (Port 25/MX) wegen dynamischer Outbound-IP problematisch ist oder du weg von Exchange SMTP Auth willst:

- `smtpUseAuth = true`
- `smtpAuthPreset = acsSmtp`
- Vaultwarden wird gesetzt auf:
  - `SMTP_HOST = smtp.azurecomm.net`
  - `SMTP_PORT = 587`
  - `SMTP_SECURITY = starttls`

**Zusätzliche Parameter:**
- `smtpUsername` = ACS SMTP Username
- `smtpPassword` = **Client Secret** deiner Entra App Registration
- `acsEntraApplicationId` = App (Client) ID
- `acsEntraServicePrincipalObjectId` = Object ID des Service Principals (für RBAC)
- optional: `acsEntraTenantId`, `acsDomainName`, `acsDataLocation`, `acsDomainManagement`

**Wichtig (DNS / Domain-Verifikation):**  
Das Template kann DNS bei deinem Provider nicht automatisch setzen. Nach dem Deployment müssen die im Portal angezeigten DNS-Records gesetzt und die Domain verifiziert werden – erst dann ist der Versand zuverlässig.

---

## Deployment

### 1) Portal („Deploy to Azure“)
- Öffne den Deploy-Button und fülle die Parameter aus.

### 2) Skript-Deployment (PowerShell)
```powershell
./scripts/deploy.ps1 -ResourceGroupName <RG-NAME> -Environment prod `
  -DomainUrl https://vault.example.com `
  -SmtpUseAuth:$false
```

---

## Parameter (wichtigste)

- **appName**: Name der Container App (Default: `vault`)
- **domainUrl**: Public URL (z. B. `https://vault.kunde.tld`)
- **allowInsecureHttp**: Default `false` (HTTPS-only)
- **cpuCores / memorySize**: Default `0.25` / `0.5`
- **vaultwardenImage**: Default `vaultwarden/server:1.35.2-alpine`

### Backup Parameter (Azure Files)
- `azureFilesBackupEnabled`: Default **true**
- `azureFilesBackupScheduleRunTime`: Default `05:30` (UTC)
- `azureFilesBackupDailyRetentionDays`: Default `30`
- `azureFilesBackupWeeklyDaysOfWeek`: Default `Sunday, Tuesday, Thursday`
- `azureFilesBackupWeeklyRetentionWeeks`: Default `12`

### PostgreSQL Backup / PITR
- Der Flexible Server ist mit `backupRetentionDays = 7` konfiguriert (Point-in-time Restore Fenster: 7 Tage).

---

## Was der Kunde bekommt (Deliverables)

### Betrieb / Service
- **Lauffähiges Vaultwarden** über eine öffentliche URL (Ingress extern, HTTPS-only)
- **Persistente Datenhaltung**
  - `/data` liegt auf Azure Files (Share)
  - Vaultwarden nutzt PostgreSQL (kein SQLite)
- **Secrets & Bootstrap**
  - `ADMIN_TOKEN` in Key Vault
  - `DATABASE_URL` in Key Vault (Least-Privilege DB User)
  - optional SMTP Secret in Key Vault (bei SMTP Auth/ACS)

### Monitoring
- Logs über **Log Analytics** (Container Apps Logging)

### Backup
- **PostgreSQL**: automatische Backups + PITR (7 Tage Fenster)
- **Azure Files**: Azure Backup aktiviert (wenn `azureFilesBackupEnabled=true`, Default: true)

---

## Wiederherstellung (High-Level)

> Im Repo ist aktuell kein voll ausformuliertes „Runbook“ (Portal/CLI Schrittfolge) enthalten – hier ist die korrekte High-Level-Logik, die sich aus den deployten Ressourcen ergibt.

### Restore 1: Container App / Revision kaputt
- Neue Revision deployen / erneut ausrollen  
  ✅ Daten bleiben erhalten (DB + Files sind extern)

### Restore 2: Datenverlust im Azure Files Share (`/data`)
- Restore über **Recovery Services Vault → Azure Files Restore** (wenn Azure Files Backup aktiv ist)

### Restore 3: Datenbankproblem (PostgreSQL)
- **Point-in-time Restore** des PostgreSQL Flexible Servers innerhalb des 7-Tage Fensters
- Danach `DATABASE_URL` (Key Vault Secret) auf den neuen Server/DNS umstellen

### Restore 4: Secrets in Key Vault gelöscht
- Key Vault hat Soft-Delete/Purge-Protection (Wiederherstellung über Portal/CLI möglich)
- Danach Container App ggf. neu starten / neue Revision

---

## Zwingend manuelle Schritte (Production)

Auch wenn das Deployment vollständig per IaC läuft, gibt es ein paar Schritte, die **nicht** sauber automatisierbar sind (DNS-Zugriff, Zertifikate, externe Credentials/Keys) und deshalb **zwingend manuell** erledigt werden müssen.

### 1) Custom Domain & Managed Certificate (Azure Container Apps)

Wenn du **eine eigene Domain** nutzen willst (z. B. `vault.example.com`), musst du im Azure Portal oder per CLI:

1. Custom Domain am **Container App** (Ingress) hinzufügen
2. die geforderten **DNS Records** (CNAME/TXT) beim Domain-Provider setzen
3. nach erfolgreicher Verifikation ein **Managed Certificate** ausstellen/zuweisen

> Ohne Custom Domain kannst du auch die standardmäßige `*.azurecontainerapps.io`-URL nutzen (inkl. TLS), dann entfällt dieser Schritt.

### 2) ACS Email Domain-Verifizierung (SPF/DKIM/DMARC)

Wenn du **ACS Email** nutzt, ist DNS-Verifikation zwingend, damit SPF/DKIM/DMARC sauber funktionieren.

- Im Email Service / Domain im Azure Portal die geforderten **DNS Records** setzen (SPF + DKIM + ggf. DMARC)
- Warten, bis die Domain im Portal als **verified** erscheint
- Erst dann produktiv Mails über `smtp.azurecomm.net` versenden (SMTP Auth)

> Die IaC erstellt die Ressourcen, aber **DNS** bleibt immer manuell.

### 3) SSO (OIDC) mit Entra ID (Vaultwarden)

Vaultwarden unterstützt SSO via **OpenID Connect**. Dafür brauchst du eine App in Entra ID:

**Entra ID / App vorbereiten**
1. App Registrierung oder Enterprise App anlegen (OIDC)
2. Redirect URI(s) setzen (Beispiele):
   - `https://<DEIN_FQDN>/identity/connect/oidc-signin`
   - `https://<DEIN_FQDN>/identity/connect/oidc-signout`
3. Client Secret erzeugen (Wert kopieren)
4. Scopes/Claims so konfigurieren, dass mindestens `email`/`preferred_username` verfügbar ist

**IaC Parameter (SSO)**
- `ssoEnabled` = `true`
- `ssoAuthority` = z. B. `https://login.microsoftonline.com/<TENANT_ID>/v2.0`
- `ssoClientId` = App (Client) ID
- `ssoClientSecret` = Secret Value (wird als Key Vault Secret abgelegt)
- Optional: `ssoOnly` = `true` (nur wenn du wirklich Passwort-Login komplett verbieten willst)
- Optional: `ssoScopes` anpassen (Default: `openid profile email offline_access User.Read`)

> Hinweis: Je nach Vaultwarden-Release bleibt ein Master-Passwort weiterhin relevant (SSO = Login-Flow für Web Vault).

### 4) Push Notifications (Mobile Clients)

Push Notifications laufen bei Vaultwarden in der Regel über die Bitwarden Push Relay Infrastruktur. Dafür brauchst du ein **Installation ID/Key Pair**:

1. Auf `https://bitwarden.com/host/` die **Installation ID** und den **Installation Key** generieren
2. In der Deployment-Konfiguration setzen:
   - `pushEnabled` = `true`
   - `pushInstallationId`
   - `pushInstallationKey` (wird als Key Vault Secret abgelegt)
   - Optional: `pushUseEuServers` = `true` (wenn du Bitwarden EU Endpoints nutzen willst)

### 5) Bitwarden Directory Connector (User/Group Sync)

Der Directory Connector ist ein **separates Tool** (läuft nicht „in Vaultwarden“). Für automatische Benutzer-/Gruppen-Synchronisation:

1. In Vaultwarden eine **Organization** anlegen (Web Vault)
2. In der Organization einen **API Key** erzeugen
3. Bitwarden Directory Connector installieren/konfigurieren (z. B. auf einer VM/Worker)
4. Connector auf deine Vaultwarden URL zeigen lassen und mit dem Org API Key verbinden
5. Sync-Job planen (Scheduler)

Optional (Governance):
- `orgCreationUsers` setzen, um einzuschränken, wer Organizations erstellen darf.

---

## Hinweis zur Repo-Struktur
- **`main.json`** ist die *einzige* maßgebliche Deploy-Datei.
- Es gibt keine separate „patched“ Template-Datei – Versionierung erfolgt über Git.

