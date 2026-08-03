<#
.SYNOPSIS
    Manages the SPO Assistant Application Customizer on SharePoint sites.

.DESCRIPTION
    Deploy, install, update, remove, and inspect the SPO Assistant Application Customizer
    on a site-by-site basis using PnP PowerShell 2.x.

    Defaults below target the site assistant API. `pnpm start` reads its own config from
    config/serve.json; this script only configures deployed (app catalog) installs.

.PARAMETER Action
    The action to perform: Deploy, Install, Update, Remove, or Status

.PARAMETER SiteUrl
    The URL of the SharePoint site to manage.

.PARAMETER TenantAdminUrl
    The URL of the SharePoint tenant admin site (required for Deploy).

.PARAMETER PackagePath
    Path to the .sppkg file. Defaults to ../sharepoint/solution/spo-assistants-spfx.sppkg.

.PARAMETER ApiBaseUrl
    Origin of the site assistant API, no trailing slash.

.PARAMETER ApiResourceUri
    The API's Entra ID Application ID URI, e.g. api://<client-id>.

.PARAMETER PnPClientId
    The Entra ID application (client) ID registered for PnP PowerShell authentication.
    Register one: https://pnp.github.io/powershell/articles/registerapplication.html

.EXAMPLE
    # Deploy package to tenant app catalog
    ./script.ps1 -Action Deploy -PnPClientId "<pnp-client-id>" -TenantAdminUrl "https://contoso-admin.sharepoint.com"

.EXAMPLE
    # Install on a specific site, using the default API base URL and resource URI
    ./script.ps1 -Action Install -PnPClientId "<pnp-client-id>" -SiteUrl "https://contoso.sharepoint.com/sites/hr"

.EXAMPLE
    # Point an existing install at a different API host
    ./script.ps1 -Action Update -PnPClientId "<pnp-client-id>" -SiteUrl "https://contoso.sharepoint.com/sites/hr" -ApiBaseUrl "https://api.example.com"

.EXAMPLE
    ./script.ps1 -Action Status -PnPClientId "<pnp-client-id>" -SiteUrl "https://contoso.sharepoint.com/sites/hr"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Deploy", "Install", "Update", "Remove", "Status")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$PnPClientId,

    [Parameter(Mandatory = $false)]
    [string]$SiteUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantAdminUrl,

    [Parameter(Mandatory = $false)]
    [string]$PackagePath,

    # Matches the apiBaseUrl in config/serve.json.
    [Parameter(Mandatory = $false)]
    [string]$ApiBaseUrl = "https://localhost:3000",

    # api:// + the site assistant API's app registration client ID.
    [Parameter(Mandatory = $false)]
    [string]$ApiResourceUri = "api://291519cc-fc6f-4cc6-8045-7db0d00a6ecb"
)

# Constants — keep in sync with config/package-solution.json and the customizer manifest.
$AppId = "b6ffb0a6-57ee-4041-9ee7-37e858083564" # solution id from package-solution.json
$ComponentId = "3a9780b3-e32e-48dc-84b0-a7882340b7e2" # SpoAssistantApplicationCustomizer.manifest.json
$CustomActionTitle = "SpoAssistant" # matches sharepoint/assets/elements.xml
$PackageName = "spo-assistants-spfx.sppkg"

function Test-PnPConnection {
    try {
        $null = Get-PnPContext -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Connect-ToSite {
    param(
        [string]$Url,
        [string]$ClientId
    )

    Write-Host "Connecting to $Url ..." -ForegroundColor Cyan
    Connect-PnPOnline -Url $Url -Interactive -ClientId $ClientId

    if (-not (Test-PnPConnection)) {
        throw "Failed to connect to $Url"
    }
    Write-Host "Connected successfully." -ForegroundColor Green
}

function Deploy-ToAppCatalog {
    param(
        [string]$AdminUrl,
        [string]$Package,
        [string]$ClientId
    )

    if (-not $AdminUrl) {
        throw "TenantAdminUrl is required for Deploy action"
    }

    if (-not $Package) {
        # Default to the solution path
        $Package = Join-Path $PSScriptRoot "../sharepoint/solution/$PackageName"
    }

    if (-not (Test-Path $Package)) {
        throw "Package file not found: $Package"
    }

    Connect-ToSite -Url $AdminUrl -ClientId $ClientId

    Write-Host "Deploying package to tenant app catalog..." -ForegroundColor Cyan

    # Add the app to the tenant app catalog
    $app = Add-PnPApp -Path $Package -Scope Tenant -Overwrite -Publish

    if ($app) {
        Write-Host "Package deployed successfully!" -ForegroundColor Green
        Write-Host "App ID: $($app.Id)" -ForegroundColor Gray
        Write-Host "App Title: $($app.Title)" -ForegroundColor Gray
        Write-Host "Approve the pending API access request in SharePoint admin center > Advanced > API access, or run ./set.ps1." -ForegroundColor Yellow
    }
    else {
        throw "Failed to deploy package to app catalog"
    }

    Disconnect-PnPOnline
}

function Get-CustomActionProperties {
    param(
        [string]$BaseUrl,
        [string]$ResourceUri
    )

    $properties = @{
        apiBaseUrl     = $BaseUrl
        apiResourceUri = $ResourceUri
    }

    return $properties | ConvertTo-Json -Compress
}

function Install-Customizer {
    param(
        [string]$Url,
        [string]$BaseUrl,
        [string]$ResourceUri,
        [string]$PnPClient
    )

    if (-not $Url) {
        throw "SiteUrl is required for Install action"
    }

    if (-not $BaseUrl) {
        throw "ApiBaseUrl is required for Install action"
    }

    if (-not $ResourceUri) {
        throw "ApiResourceUri is required for Install action"
    }

    Connect-ToSite -Url $Url -ClientId $PnPClient
    Install-App

    # Check if already installed
    $existingAction = Get-PnPCustomAction -Scope Site | Where-Object { $_.ClientSideComponentId -eq $ComponentId }

    if ($existingAction) {
        Write-Host "Customizer is already installed on this site. Use 'Update' action to modify configuration." -ForegroundColor Yellow
        Disconnect-PnPOnline
        return
    }

    $clientSideComponentProperties = Get-CustomActionProperties -BaseUrl $BaseUrl -ResourceUri $ResourceUri

    Write-Host "Installing SPO Assistant customizer..." -ForegroundColor Cyan
    Write-Host "Properties: $clientSideComponentProperties" -ForegroundColor Gray

    Add-PnPCustomAction -Name $CustomActionTitle `
        -Title $CustomActionTitle `
        -Location "ClientSideExtension.ApplicationCustomizer" `
        -ClientSideComponentId $ComponentId `
        -ClientSideComponentProperties $clientSideComponentProperties `
        -Scope Site

    Write-Host "Customizer installed successfully!" -ForegroundColor Green

    Disconnect-PnPOnline
}

function Update-Customizer {
    param(
        [string]$Url,
        [string]$BaseUrl,
        [string]$ResourceUri,
        [string]$PnPClient
    )

    if (-not $Url) {
        throw "SiteUrl is required for Update action"
    }

    Connect-ToSite -Url $Url -ClientId $PnPClient

    # Find the existing custom action
    $existingAction = Get-PnPCustomAction -Scope Site | Where-Object { $_.ClientSideComponentId -eq $ComponentId }

    if (-not $existingAction) {
        Write-Host "Customizer is not installed on this site. Use 'Install' action first." -ForegroundColor Yellow
        Disconnect-PnPOnline
        return
    }

    # Get current properties
    $currentProps = @{}
    if ($existingAction.ClientSideComponentProperties) {
        $currentProps = $existingAction.ClientSideComponentProperties | ConvertFrom-Json -AsHashtable
    }

    # Update with new values (keep existing if not provided)
    if ($BaseUrl) { $currentProps.apiBaseUrl = $BaseUrl }
    if ($ResourceUri) { $currentProps.apiResourceUri = $ResourceUri }

    $clientSideComponentProperties = $currentProps | ConvertTo-Json -Compress

    Write-Host "Updating SPO Assistant customizer..." -ForegroundColor Cyan
    Write-Host "New Properties: $clientSideComponentProperties" -ForegroundColor Gray

    # Remove and re-add (PnP doesn't have a direct update for custom action properties)
    Remove-PnPCustomAction -Identity $existingAction.Id -Scope Site -Force

    Add-PnPCustomAction -Name $CustomActionTitle `
        -Title $CustomActionTitle `
        -Location "ClientSideExtension.ApplicationCustomizer" `
        -ClientSideComponentId $ComponentId `
        -ClientSideComponentProperties $clientSideComponentProperties `
        -Scope Site

    Write-Host "Customizer updated successfully!" -ForegroundColor Green

    Disconnect-PnPOnline
}

function Remove-Customizer {
    param(
        [string]$Url,
        [string]$PnPClient
    )

    if (-not $Url) {
        throw "SiteUrl is required for Remove action"
    }

    Connect-ToSite -Url $Url -ClientId $PnPClient

    # Find the existing custom action
    $existingAction = Get-PnPCustomAction -Scope Site | Where-Object { $_.ClientSideComponentId -eq $ComponentId }

    if (-not $existingAction) {
        Write-Host "Customizer is not installed on this site." -ForegroundColor Yellow
        Disconnect-PnPOnline
        return
    }

    Write-Host "Removing SPO Assistant customizer..." -ForegroundColor Cyan

    Remove-PnPCustomAction -Identity $existingAction.Id -Scope Site -Force

    Write-Host "Customizer removed successfully!" -ForegroundColor Green

    Disconnect-PnPOnline
}

function Get-CustomizerStatus {
    param(
        [string]$Url,
        [string]$PnPClient
    )

    if (-not $Url) {
        throw "SiteUrl is required for Status action"
    }

    Connect-ToSite -Url $Url -ClientId $PnPClient

    # Find the existing custom action
    $existingAction = Get-PnPCustomAction -Scope Site | Where-Object { $_.ClientSideComponentId -eq $ComponentId }

    if (-not $existingAction) {
        Write-Host "Customizer is NOT installed on this site." -ForegroundColor Yellow
    }
    else {
        Write-Host "Customizer IS installed on this site." -ForegroundColor Green
        Write-Host ""
        Write-Host "Details:" -ForegroundColor Cyan
        Write-Host "  ID: $($existingAction.Id)" -ForegroundColor Gray
        Write-Host "  Name: $($existingAction.Name)" -ForegroundColor Gray
        Write-Host "  Component ID: $($existingAction.ClientSideComponentId)" -ForegroundColor Gray

        if ($existingAction.ClientSideComponentProperties) {
            Write-Host "  Properties:" -ForegroundColor Gray
            $props = $existingAction.ClientSideComponentProperties | ConvertFrom-Json
            $props.PSObject.Properties | ForEach-Object {
                Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor Gray
            }
        }
    }

    Disconnect-PnPOnline
}

function Install-App {

    try {
        Install-PnPApp -Identity $AppId
    } catch {
        # Expected when the solution is deployed tenant-wide (skipFeatureDeployment) —
        # there is nothing to install per site.
        Write-Host $_
    }
}

# Main execution
try {
    # Verify PnP.PowerShell module is installed
    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        throw "PnP.PowerShell module is not installed. Install it with: Install-Module PnP.PowerShell -Scope CurrentUser"
    }

    switch ($Action) {
        "Deploy" {
            Deploy-ToAppCatalog -AdminUrl $TenantAdminUrl -Package $PackagePath -ClientId $PnPClientId
        }
        "Install" {
            Install-Customizer -Url $SiteUrl -BaseUrl $ApiBaseUrl -ResourceUri $ApiResourceUri -PnPClient $PnPClientId
        }
        "Update" {
            Update-Customizer -Url $SiteUrl -BaseUrl $ApiBaseUrl -ResourceUri $ApiResourceUri -PnPClient $PnPClientId
        }
        "Remove" {
            Remove-Customizer -Url $SiteUrl -PnPClient $PnPClientId
        }
        "Status" {
            Get-CustomizerStatus -Url $SiteUrl -PnPClient $PnPClientId
        }
    }
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
