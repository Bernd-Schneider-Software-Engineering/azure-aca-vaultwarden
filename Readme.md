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

## Wiederherstellung / Disaster-Recovery (Runbook)

Dieses Repo deployt Persistenz **außerhalb** der Container App:

- **PostgreSQL Flexible Server** (Datenbank)
- **Azure Files Share** (`/data`) (Attachments/Icons/Send/SQLite etc. – je nach Vaultwarden-Config)
- **Key Vault** (Secrets; Soft-Delete/Purge-Protection)

> Grundprinzip: **Container App ist austauschbar**, Daten liegen extern. Restore bedeutet fast immer: **Daten wiederherstellen** und danach **Container App auf die wiederhergestellten Daten zeigen lassen** (neue Revision).

### 0) Vor jedem Restore (Checkliste)

1. **Incident vs. Drill**: willst du _Original Location_ überschreiben oder bewusst _Alternate Location_ (besser für Tests)?
2. **Schreibzugriffe stoppen (wenn nötig)**: z. B. Container App temporär auf `minReplicas=0` / Wartungsfenster, damit während des Restores keine inkonsistenten Writes passieren.
3. **Inventar notieren** (für Nachvollziehbarkeit):
   - Resource Group
   - Container App Name + aktuelle Revision
   - PostgreSQL Servername
   - Storage Account + File Share Name
   - Recovery Services Vault Name
   - Key Vault Name

---

### 1) Container App / Revision kaputt (kein Datenverlust)

**Ziel:** App wieder online bringen, ohne Daten-Restore.

- Neue Revision deployen (erneutes ARM-Deployment) oder letzte funktionierende Revision wieder hochziehen.
- Erwartung: DB + Files bleiben erhalten (extern).

---

### 2) Azure Files Restore (`/data`)

> Voraussetzung: `azureFilesBackupEnabled=true` (im Template default: `true`). Dann existiert ein **Recovery Services Vault** + Protection für den File Share.

#### 2.1 Backup-Item & Recovery Points finden (CLI)

```bash
RG="<resource-group>"
VAULT="$(az resource list -g "$RG" --resource-type Microsoft.RecoveryServices/vaults --query "[0].name" -o tsv)"

# Container + Item ermitteln
CONTAINER="$(az backup container list -g "$RG" --vault-name "$VAULT" --backup-management-type AzureStorage --query "[0].name" -o tsv)"
ITEM="$(az backup item list -g "$RG" --vault-name "$VAULT" --workload-type AzureFileShare --query "[0].name" -o tsv)"

# Recovery Points anzeigen
az backup recoverypoint list -g "$RG" --vault-name "$VAULT" --container-name "$CONTAINER" --item-name "$ITEM" -o table
```

#### 2.2 Restore ausführen (empfohlen: **Alternate Location** für Drill)

```bash
# Beispiel: Restore kompletten Share in ein *anderes* File Share / Folder (Drill)
TARGET_SA="<target-storage-account>"
TARGET_SHARE="<target-file-share>"
TARGET_FOLDER="restore-$(date +%Y%m%d-%H%M)"
RP="<recovery-point-id>"

az backup restore restore-azurefileshare   -g "$RG" --vault-name "$VAULT"   --rp-name "$RP"   --container-name "$CONTAINER"   --item-name "$ITEM"   --restore-mode alternatelocation   --target-storage-account "$TARGET_SA"   --target-file-share "$TARGET_SHARE"   --target-folder "$TARGET_FOLDER"   --resolve-conflict overwrite   -o table
```

**Original Location Restore** (overschreibt den bestehenden Share) ist möglich, ist aber für Tests riskant. Wenn du wirklich „zurückdrehen“ willst, nutze `--restore-mode originallocation`.

#### 2.3 Vaultwarden wieder anbinden

- **Original Location Restore**: i. d. R. keine App-Änderung nötig → neue Revision ausrollen / App neu starten.
- **Alternate Location Restore**: du musst Vaultwarden auf den restored Share zeigen lassen (Volume/Share ändern) → neue Revision mit angepasstem Volume-Mount.

---

### 3) PostgreSQL Restore (PITR)

> Flexible Server PITR erstellt **einen neuen Server**. Danach muss `DATABASE_URL` (Key Vault Secret) auf den neuen FQDN zeigen.

#### 3.1 PITR durchführen (CLI)

```bash
RG="<resource-group>"
SRC_PG="<source-flexible-server-name>"
NEW_PG="<restored-flexible-server-name>"
RESTORE_TIME_UTC="2026-02-17T20:15:00Z"   # innerhalb der Backup-Retention
LOCATION="<azure-region>"

az postgres flexible-server restore   -g "$RG"   --name "$NEW_PG"   --source-server "$SRC_PG"   --restore-time "$RESTORE_TIME_UTC"   --location "$LOCATION"
```

#### 3.2 `DATABASE_URL` auf neuen Server umstellen

Dieses Repo nutzt:
- Container App Secret: `database-url`
- Key Vault Secret: `vw-database-url`

Vorgehen (Beispiel, Wert als Platzhalter):

```bash
KV="<key-vault-name>"
DB_URL="<postgres-connection-string>"

az keyvault secret set --vault-name "$KV" --name "vw-database-url" --value "$DB_URL"
```

Danach Container App neu ausrollen (neue Revision / Restart), damit die App den aktualisierten Secret-Value zieht.

---

### 4) Key Vault Secrets gelöscht

- Key Vault ist mit **Soft-Delete/Purge-Protection** deployt → Wiederherstellung über Portal/CLI möglich.
- Nach Restore ggf. neue Revision ausrollen.

---

### 5) 1x Restore-Probe (empfohlen – „Drill“)

**Ziel:** Einmal nach Go-Live nachweisen, dass Restore in der Praxis klappt.

1. **Azure Files**: Recovery Point auswählen → Restore in **Alternate Location** (neuer File Share oder Unterordner).
2. **Postgres**: PITR in **neuen** Flexible Server.
3. **Test-Revision**: Vaultwarden als neue Revision starten, die auf die restored Ressourcen zeigt.
4. **Smoke**: Login + Vault lesen + ein Attachment anlegen.
5. **Cleanup**: Test-Revision + restored Test-Ressourcen löschen (wenn nicht mehr benötigt).

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


