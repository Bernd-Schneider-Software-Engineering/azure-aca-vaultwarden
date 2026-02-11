param(
  [Parameter(Mandatory=$true)]
  [string]$ResourceGroupName,

  # Public URL of Vaultwarden, e.g. https://vault.example.com
  [Parameter(Mandatory=$false)]
  [string]$DomainUrl,

  # SMTP settings (required by the template)
  [Parameter(Mandatory=$false)]
  [string]$SmtpFrom,

  [Parameter(Mandatory=$false)]
  [string]$SmtpUsername,

  [Parameter(Mandatory=$false)]
  [securestring]$SmtpPassword,

  [ValidateSet("prod","test","dev")]
  [string]$Environment = "prod",

  [string]$BsseRef = ""
)

# Requires: Azure CLI (az) and (optionally) git
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
  throw "Azure CLI (az) wurde nicht gefunden. Bitte Azure CLI installieren und 'az login' ausführen."
}

if ([string]::IsNullOrWhiteSpace($BsseRef)) {
  if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
      $BsseRef = (git describe --tags --always --dirty 2>$null).Trim()
      if ([string]::IsNullOrWhiteSpace($BsseRef)) {
        $BsseRef = (git rev-parse --short HEAD 2>$null).Trim()
      }
    } catch { }
  }
}

if ([string]::IsNullOrWhiteSpace($BsseRef)) {
  # Fallback – Template selbst versucht zusätzlich aus templateLink zu lesen
  $BsseRef = ""
}

Write-Host "Deploying with tags: Environment=$Environment, bsse:ref=$BsseRef"

if ([string]::IsNullOrWhiteSpace($DomainUrl)) {
  $DomainUrl = Read-Host "Domain URL (e.g. https://vault.example.com)"
}

if ([string]::IsNullOrWhiteSpace($SmtpFrom)) {
  $SmtpFrom = Read-Host "SMTP From (e.g. vault@yourdomain.tld)"
}

if ([string]::IsNullOrWhiteSpace($SmtpUsername)) {
  $SmtpUsername = Read-Host "SMTP Username"
}

if (-not $SmtpPassword) {
  $SmtpPassword = Read-Host "SMTP Password" -AsSecureString
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TemplatePath = Join-Path $RepoRoot "main.json"

if (-not (Test-Path $TemplatePath)) {
  throw "Template nicht gefunden: $TemplatePath"
}

$smtpPasswordPlain = $null
$paramFile = Join-Path ([System.IO.Path]::GetTempPath()) ("vaultwarden.parameters.{0}.json" -f ([System.Guid]::NewGuid().ToString("N")))

try {
  # Convert securestring to plain only for the temporary parameters file (file will be deleted).
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SmtpPassword)
  try {
    $smtpPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
  }

  $params = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
      environment = @{ value = $Environment }
      bsseRef     = @{ value = $BsseRef }
      domainUrl   = @{ value = $DomainUrl }
      smtpFrom    = @{ value = $SmtpFrom }
      smtpUsername= @{ value = $SmtpUsername }
      smtpPassword= @{ value = $smtpPasswordPlain }
    }
  }

  $params | ConvertTo-Json -Depth 10 | Set-Content -Path $paramFile -Encoding UTF8

  az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $TemplatePath `
    --parameters @$paramFile
}
finally {
  if (Test-Path $paramFile) {
    Remove-Item $paramFile -Force -ErrorAction SilentlyContinue
  }
  $smtpPasswordPlain = $null
}
