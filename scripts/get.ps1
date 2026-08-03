<#
.SYNOPSIS
    Lists the delegated scopes granted to SPFx for the site assistant API.

.DESCRIPTION
    https://laurakokkarinen.com/managing-sharepoint-framework-api-permissions-with-powershell/

.PARAMETER ResourceAppIds
    Client ID(s) of the resource app(s) to report on. Defaults to the site assistant API.

.PARAMETER TenantId
    Tenant to sign in to.

.EXAMPLE
    # The usual case: report on the site assistant API
    ./get.ps1

.EXAMPLE
    # Check the API alongside Microsoft Graph
    ./get.ps1 -ResourceAppIds "291519cc-fc6f-4cc6-8045-7db0d00a6ecb","00000003-0000-0000-c000-000000000000"
#>

[CmdletBinding()]
param(
    [string[]]$ResourceAppIds = @("291519cc-fc6f-4cc6-8045-7db0d00a6ecb"), # site assistant API app registration

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
    # A grant found for a previous resource must not leak into this iteration.
    $resourceGrant = $null

    # Get the SPFx Service Principal
    $spfx = Get-MgServicePrincipal -Filter "appid eq '$spfxAppId'" -ErrorAction Stop
    # Get the endpoint service princpal (required to identify the object ID)
    $resource = Get-MgServicePrincipal -Filter "appid eq '$resourceAppId'" -ErrorAction Stop

    if ($null -eq $resource) {
      Write-Host "No service principal found for app $resourceAppId in this tenant." -ForegroundColor Yellow
      continue
    }

    # Get the scopes granted for the endpoint
    $spfxGrants = Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $spfx.Id -ErrorAction Stop
    foreach ($spfxGrant in $spfxGrants) {
      if ($spfxGrant.ResourceId -eq $resource.Id) {
        $resourceGrant = $spfxGrant
        break
      }
    }
    if ($null -ne $resourceGrant -and $resourceGrant.Scope.Length -gt 0) {
      Write-Host "The following scopes have been granted for app $($resource.DisplayName) ($resourceAppId): $($resourceGrant.Scope.Trim() -replace ' ', ', ')."
    }
    else {
      Write-Host "No scopes have been granted for app $($resource.DisplayName) ($resourceAppId)."
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
