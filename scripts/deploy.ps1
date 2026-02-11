param(
  [Parameter(Mandatory=$true)]
  [string]$ResourceGroupName,

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

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$TemplatePath = Join-Path $RepoRoot "main.json"

if (-not (Test-Path $TemplatePath)) {
  throw "Template nicht gefunden: $TemplatePath"
}

az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file $TemplatePath `
  --parameters environment=$Environment bsseRef=$BsseRef
