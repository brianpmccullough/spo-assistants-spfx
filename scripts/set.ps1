<#
.SYNOPSIS
    Grants SPFx the delegated scopes it needs on the site assistant API.

.DESCRIPTION
    Equivalent to approving the pending request in SharePoint admin center > Advanced >
    API access, but scripted.

    https://laurakokkarinen.com/managing-sharepoint-framework-api-permissions-with-powershell/

.PARAMETER ResourceAppIds
    Client ID(s) of the resource app(s) to grant on. Defaults to the site assistant API.

.PARAMETER Scopes
    Delegated scopes to grant. Must match scopes the resource app actually exposes.

.PARAMETER TenantId
    Tenant to sign in to.

.EXAMPLE
    # Grants user_impersonation on the site assistant API, then confirm with ./get.ps1
    ./set.ps1

.EXAMPLE
    # Grant more than the default scope
    ./set.ps1 -Scopes "user_impersonation","Files.Read"
#>

[CmdletBinding()]
param(
    [string[]]$ResourceAppIds = @("291519cc-fc6f-4cc6-8045-7db0d00a6ecb"), # site assistant API app registration

    [string[]]$Scopes = @("user_impersonation"),

    [string]$TenantId = "f57cc439-ce28-47f8-9734-f707b7809a88"
)

$spfxAppId = "08e18876-6177-487e-b8b5-cf950c1e598c" # SharePoint Online Web Client Extensibility

# Prompt to install the required modules if not yet installed
if ($null -eq (Get-Module -ListAvailable -Name Microsoft.Graph.Applications) -or $null -eq (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.SignIns)) {
  $response = Read-Host -Prompt "Running this script requires Microsoft.Graph modules that are not yet installed. Install now? (Y/N)"
  if ($response -eq "Y") {
    if ($null -eq (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
      Install-Module -Name Microsoft.Graph.Applications -Scope CurrentUser -Force -AllowClobber
    }
    if ($null -eq (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.SignIns)) {
      Install-Module -Name Microsoft.Graph.Identity.SignIns -Scope CurrentUser -Force -AllowClobber
    }
  }
  else {
    Write-Host "The script cannot continue without the Microsoft.Graph modules. Exiting."
    exit
  }
}

$connectArgs = @{ Scopes = @("Application.ReadWrite.All", "Directory.ReadWrite.All"); NoWelcome = $true }
if ($TenantId) { $connectArgs.TenantId = $TenantId }
Connect-MgGraph @connectArgs

try {
  foreach ($resourceAppId in $ResourceAppIds) {
    # Get the SPFx Service Principal
    $spfx = Get-MgServicePrincipal -Filter "appid eq '$spfxAppId'" -ErrorAction Stop
    # Get the endpoint service princpal (required to identify the object ID)
    $resource = Get-MgServicePrincipal -Filter "appid eq '$resourceAppId'" -ErrorAction Stop

    if ($null -eq $resource) {
      Write-Host "No service principal found for app $resourceAppId in this tenant." -ForegroundColor Yellow
      continue
    }

    foreach ($scope in $Scopes) {
      # Re-read per scope: the grant object is stale after an update below.
      $resourceGrant = $null
      $spfxGrants = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $spfx.Id -ErrorAction Stop
      foreach ($spfxGrant in $spfxGrants) {
        if ($spfxGrant.ResourceId -eq $resource.Id) {
          $resourceGrant = $spfxGrant
          break
        }
      }
      # If some scopes have already been granted for the endpoint, we check if the scope we are about to add already exists there
      if ($null -ne $resourceGrant) {
        # Compare whole scope names — Select-String would match a substring of another scope.
        if ($resourceGrant.Scope -split '\s+' -contains $scope) {
          Write-Host "Scope $scope has already been granted for app $($resource.DisplayName) ($resourceAppId)."
          continue
        }
        # The scope does not yet exist; add it to the property and update it
        $updatedScope = "$($resourceGrant.Scope) $scope".Trim()
        Update-MgOauth2PermissionGrant -OAuth2PermissionGrantId $resourceGrant.Id -Scope $updatedScope -ErrorAction Stop | Out-Null
      }
      # Otherwise, create a new object with the scope
      else {
        $params = @{
          "clientId"    = $spfx.id
          "consentType" = "AllPrincipals"
          "resourceId"  = $resource.id
          "scope"       = $scope
        }
        New-MgOauth2PermissionGrant -BodyParameter $params -ErrorAction Stop | Out-Null
      }
      Write-Host "Scope $scope granted for app $($resource.DisplayName) ($resourceAppId)."
    }
  }
}
catch {
  Write-Host "The following error occurred: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
  $null = Disconnect-MgGraph # Assigning the output to a variable hides it from the terminal
  Write-Host "Command completed."
}
