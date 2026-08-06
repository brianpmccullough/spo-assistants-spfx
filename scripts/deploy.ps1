<#
.SYNOPSIS
    Full lifecycle management of the SPO Assistant Application Customizer on one or more sites.

.DESCRIPTION
    Everything a site needs, driven entirely from PnP.PowerShell — no elements.xml, no
    <CustomAction> feature framework. For each site the Deploy action will, idempotently:

      1. create the site collection app catalog if the site does not have one;
      2. upload and publish the .sppkg into that site collection app catalog;
      3. install the app on the site (or upgrade it if an older version is installed);
      4. add the ClientSideExtension.ApplicationCustomizer custom action, or rewrite it
         when its ClientSideComponentProperties have changed.

    Remove reverses steps 4 → 1 (the app catalog itself is only removed with
    -RemoveAppCatalog). Status reports without changing anything.

    Re-running Deploy against an already-deployed site is safe and is the normal way to
    ship a new build or change the API host.

    Runs interactively at a developer's terminal (-Interactive) or unattended in CI with an
    Entra app-only certificate (-CertificateBase64Encoded / -CertificatePath).

.PARAMETER Action
    Deploy (default), Remove, or Status.

.PARAMETER SiteUrl
    One or more site URLs to act on, e.g. https://contoso.sharepoint.com/sites/home.

.PARAMETER PackagePath
    Path to the .sppkg. Defaults to ../sharepoint/solution/spo-assistants-spfx.sppkg.

.PARAMETER ApiBaseUrl
    Origin of the site assistant API, no trailing slash. Written to the custom action's
    ClientSideComponentProperties, so it can differ per site.

.PARAMETER ApiResourceUri
    The API's Entra ID Application ID URI, e.g. api://<client-id>.

.PARAMETER Properties
    Extra ClientSideComponentProperties to merge in (chatUrl, actions, theme, ...).
    Wins over the ApiBaseUrl / ApiResourceUri parameters for keys it sets.

.PARAMETER TenantAdminUrl
    SharePoint admin center URL. Only needed to create or remove a site collection app
    catalog; derived from the site URL (contoso -> contoso-admin) when not supplied.

.PARAMETER RemoveAppCatalog
    Remove action only: also remove the site collection app catalog from the site.

.PARAMETER ClientId
    Entra ID application (client) ID used to authenticate PnP.PowerShell.
    https://pnp.github.io/powershell/articles/registerapplication.html

.PARAMETER Tenant
    Tenant name or ID (e.g. contoso.onmicrosoft.com). Required for app-only auth.

.PARAMETER Interactive
    Sign in interactively in a browser instead of using a certificate.

.PARAMETER CertificateBase64Encoded
    Base64-encoded PFX for app-only auth. Suits a CI secret.

.PARAMETER CertificatePath
    Path to a PFX on disk, as an alternative to -CertificateBase64Encoded.

.PARAMETER CertificatePassword
    Password protecting the PFX, if it has one.

.EXAMPLE
    # Interactive: ship the current build to two sites
    ./deploy.ps1 -Interactive -ClientId <pnp-client-id> `
        -SiteUrl https://contoso.sharepoint.com/sites/home, https://contoso.sharepoint.com/sites/hr `
        -ApiBaseUrl https://api.contoso.com

.EXAMPLE
    # Unattended (CI): same thing with an app-only certificate
    ./deploy.ps1 -ClientId $env:SPO_CLIENT_ID -Tenant $env:SPO_TENANT `
        -CertificateBase64Encoded $env:SPO_CERT_B64 -CertificatePassword $env:SPO_CERT_PASSWORD `
        -SiteUrl https://contoso.sharepoint.com/sites/home

.EXAMPLE
    # Tear down completely, app catalog included
    ./deploy.ps1 -Action Remove -Interactive -ClientId <pnp-client-id> `
        -SiteUrl https://contoso.sharepoint.com/sites/hr -RemoveAppCatalog

.EXAMPLE
    ./deploy.ps1 -Action Status -Interactive -ClientId <pnp-client-id> -SiteUrl https://contoso.sharepoint.com/sites/home
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("Deploy", "Remove", "Status")]
    [string]$Action = "Deploy",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$SiteUrl,

    [string]$PackagePath,

    # Matches the deployed API host; config/serve.json carries the `pnpm start` equivalent.
    [string]$ApiBaseUrl = "https://container-app-spo-assistants.agreeablesand-e9283835.swedencentral.azurecontainerapps.io",

    # api:// + the site assistant API's app registration client ID.
    [string]$ApiResourceUri = "api://291519cc-fc6f-4cc6-8045-7db0d00a6ecb",

    [hashtable]$Properties = @{},

    [string]$TenantAdminUrl,

    [switch]$RemoveAppCatalog,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [string]$Tenant,

    [switch]$Interactive,

    [string]$CertificateBase64Encoded,

    [string]$CertificatePath,

    [string]$CertificatePassword
)

$ErrorActionPreference = "Stop"

# Constants — keep in sync with config/package-solution.json and the customizer manifest.
$AppId = "b6ffb0a6-57ee-4041-9ee7-37e858083564" # solution id from package-solution.json
$ComponentId = "3a9780b3-e32e-48dc-84b0-a7882340b7e2" # SpoAssistantApplicationCustomizer.manifest.json
$SolutionName = "spo-assistants-spfx-client-side-solution" # solution.name from package-solution.json
$CustomActionName = "SpoAssistant"
$CustomActionLocation = "ClientSideExtension.ApplicationCustomizer"
$PackageName = "spo-assistants-spfx.sppkg"

# The app catalog list is provisioned asynchronously; this is how long we wait for it.
$AppCatalogTimeoutSeconds = 120
$AppCatalogPollSeconds = 5

function Write-Step { param([string]$Message) Write-Host "  $Message" -ForegroundColor Cyan }
function Write-Ok { param([string]$Message) Write-Host "  $Message" -ForegroundColor Green }
function Write-Skip { param([string]$Message) Write-Host "  $Message" -ForegroundColor DarkGray }
function Write-Warn { param([string]$Message) Write-Host "  $Message" -ForegroundColor Yellow }

function Get-ErrorText {
    <#
        CSOM and MSAL failures often carry an empty or opaque Message ("{}") with the real
        cause an inner exception or two down, so walk the chain and keep the type names.
    #>
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    $parts = @()
    $exception = $ErrorRecord.Exception
    while ($exception) {
        $message = $exception.Message
        if (-not [string]::IsNullOrWhiteSpace($message) -and $message -ne "{}") {
            $parts += "$($exception.GetType().Name): $message"
        }
        $exception = $exception.InnerException
    }

    if ($parts.Count -eq 0) {
        # Nothing usable in the chain — fall back to how PowerShell would have printed it.
        $parts += ($ErrorRecord | Out-String).Trim()
    }

    return $parts -join " -> "
}

function Add-SupportedParameter {
    <#
        Adds parameters to a splat only if the installed cmdlet actually accepts them, so
        the script runs on PnP.PowerShell 2.x and 3.x alike. 3.x added -Connection to
        Disconnect-PnPOnline and -Force to Remove-PnPApp; passing either to 2.x is a
        hard error.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][hashtable]$Splat,
        [Parameter(Mandatory = $true)][hashtable]$Optional
    )

    $supported = (Get-Command $Command).Parameters
    foreach ($key in $Optional.Keys) {
        if ($supported.ContainsKey($key)) { $Splat[$key] = $Optional[$key] }
    }

    return $Splat
}

function Disconnect-Target {
    param($Connection)

    # On 2.x there is nothing safe to disconnect: -ReturnConnection never makes a
    # connection "current", and an unqualified Disconnect-PnPOnline would target whatever
    # is. Those connections are released when the process exits.
    $splat = Add-SupportedParameter -Command "Disconnect-PnPOnline" -Splat @{} -Optional @{ Connection = $Connection }
    if ($splat.Count -gt 0) { Disconnect-PnPOnline @splat }
}

function Connect-Target {
    <#
        One connection factory for every URL this script touches (sites and the admin
        center), so the auth mode is decided in exactly one place.
    #>
    param([Parameter(Mandatory = $true)][string]$Url)

    $connectArgs = @{
        Url              = $Url
        ClientId         = $ClientId
        ReturnConnection = $true
        WarningAction    = "SilentlyContinue"
    }

    if ($Interactive) {
        $connectArgs.Interactive = $true
    }
    else {
        if (-not $Tenant) {
            throw "-Tenant is required for app-only authentication. Pass -Interactive to sign in with a browser instead."
        }

        $connectArgs.Tenant = $Tenant

        if ($CertificateBase64Encoded) {
            $connectArgs.CertificateBase64Encoded = $CertificateBase64Encoded
        }
        elseif ($CertificatePath) {
            if (-not (Test-Path $CertificatePath)) {
                throw "Certificate not found: $CertificatePath"
            }
            $connectArgs.CertificatePath = $CertificatePath
        }
        else {
            throw "Supply -CertificateBase64Encoded or -CertificatePath for app-only authentication, or pass -Interactive."
        }

        if ($CertificatePassword) {
            $connectArgs.CertificatePassword = ConvertTo-SecureString $CertificatePassword -AsPlainText -Force
        }
    }

    return Connect-PnPOnline @connectArgs
}

function Resolve-TenantAdminUrl {
    param([Parameter(Mandatory = $true)][string]$Url)

    if ($TenantAdminUrl) { return $TenantAdminUrl }

    $siteHost = ([Uri]$Url).Host
    if ($siteHost -notmatch '^(?<tenant>[^.]+)\.sharepoint\.(?<suffix>.+)$') {
        throw "Cannot derive the admin center URL from $Url. Pass -TenantAdminUrl explicitly."
    }

    return "https://$($Matches.tenant)-admin.sharepoint.$($Matches.suffix)"
}

function Test-SiteCollectionAppCatalog {
    param([Parameter(Mandatory = $true)]$Connection)

    # The site collection app catalog is a list at <site>/AppCatalog. Asking for the list
    # is cheaper than Get-PnPSiteCollectionAppCatalog, which needs tenant admin rights.
    $list = Get-PnPList -Identity "AppCatalog" -Connection $Connection -ErrorAction SilentlyContinue
    return $null -ne $list
}

function New-SiteCollectionAppCatalog {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)]$Connection
    )

    $adminUrl = Resolve-TenantAdminUrl -Url $Url
    Write-Step "Creating the site collection app catalog (via $adminUrl) ..."

    $adminConnection = Connect-Target -Url $adminUrl
    try {
        Add-PnPSiteCollectionAppCatalog -Site $Url -Connection $adminConnection
    }
    finally {
        Disconnect-Target -Connection $adminConnection
    }

    $deadline = (Get-Date).AddSeconds($AppCatalogTimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SiteCollectionAppCatalog -Connection $Connection) {
            Write-Ok "App catalog created."
            return
        }
        Start-Sleep -Seconds $AppCatalogPollSeconds
    }

    throw "The site collection app catalog for $Url did not appear within $AppCatalogTimeoutSeconds seconds."
}

function Remove-SiteCollectionAppCatalog {
    param([Parameter(Mandatory = $true)][string]$Url)

    $adminUrl = Resolve-TenantAdminUrl -Url $Url
    Write-Step "Removing the site collection app catalog (via $adminUrl) ..."

    $adminConnection = Connect-Target -Url $adminUrl
    try {
        Remove-PnPSiteCollectionAppCatalog -Site $Url -Connection $adminConnection
        Write-Ok "App catalog removed."
    }
    finally {
        Disconnect-Target -Connection $adminConnection
    }
}

function Get-SolutionApp {
    <#
        The Id an app catalog reports is the catalog entry's own id, not the solution's
        ProductID, so match on the solution name and use the returned Id for every
        Install/Update/Uninstall/Remove that follows.
    #>
    param([Parameter(Mandatory = $true)]$Connection)

    return Get-PnPApp -Scope Site -Connection $Connection -ErrorAction SilentlyContinue |
        Where-Object { $_.Title -eq $SolutionName -or $_.Id -eq $AppId } |
        Select-Object -First 1
}

function Test-AppInstalled {
    # This PnP version leaves Installed empty rather than $false; InstalledVersion is the
    # signal that actually distinguishes "in the catalog" from "installed on the site".
    param($App)

    return $null -ne $App -and -not [string]::IsNullOrWhiteSpace($App.InstalledVersion)
}

function Install-OrUpgradeApp {
    <#
        Publishing with -Overwrite briefly leaves the catalog entry reporting no
        InstalledVersion even when the app is installed, so the flags decide which call to
        try first, not whether the app is installed. SharePoint is the authority: if it
        rejects the install as already present, upgrade instead.
    #>
    param(
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)]$App
    )

    if (Test-AppInstalled -App $App) {
        if (-not $App.CanUpgrade -and $App.InstalledVersion -eq $App.AppCatalogVersion) {
            Write-Skip "App already installed at $($App.InstalledVersion)."
            return
        }

        Write-Step "Upgrading the installed app from $($App.InstalledVersion) to $($App.AppCatalogVersion) ..."
        Update-PnPApp -Identity $App.Id -Scope Site -Connection $Connection | Out-Null
        Write-Ok "App upgraded."
        return
    }

    try {
        Write-Step "Installing the app on the site ..."
        Install-PnPApp -Identity $App.Id -Scope Site -Connection $Connection | Out-Null
        Write-Ok "App installed."
    }
    catch {
        if ((Get-ErrorText -ErrorRecord $_) -notmatch "already exists") { throw }

        Write-Skip "App was already installed; upgrading to $($App.AppCatalogVersion) instead."
        Update-PnPApp -Identity $App.Id -Scope Site -Connection $Connection | Out-Null
        Write-Ok "App upgraded."
    }
}

function Resolve-PackagePath {
    if ($PackagePath) {
        if (-not (Test-Path $PackagePath)) { throw "Package file not found: $PackagePath" }
        return (Resolve-Path $PackagePath).Path
    }

    $default = Join-Path $PSScriptRoot "../sharepoint/solution/$PackageName"
    if (-not (Test-Path $default)) {
        throw "Package file not found: $default. Run 'pnpm run build' first, or pass -PackagePath."
    }
    return (Resolve-Path $default).Path
}

function Get-DesiredProperties {
    $desired = @{
        apiBaseUrl     = $ApiBaseUrl
        apiResourceUri = $ApiResourceUri
    }

    # Caller-supplied values win, so -Properties can override or extend the defaults.
    foreach ($key in $Properties.Keys) { $desired[$key] = $Properties[$key] }

    # Sorted so an unchanged configuration always serializes identically and compares equal.
    $ordered = [ordered]@{}
    foreach ($key in ($desired.Keys | Sort-Object)) { $ordered[$key] = $desired[$key] }

    return $ordered | ConvertTo-Json -Compress
}

function Get-Customizer {
    param([Parameter(Mandatory = $true)]$Connection)

    return Get-PnPCustomAction -Scope Site -Connection $Connection |
        Where-Object { $_.ClientSideComponentId -eq $ComponentId }
}

function Set-Customizer {
    <# Add the custom action, or rewrite it when its properties have drifted. #>
    param(
        [Parameter(Mandatory = $true)]$Connection,
        [Parameter(Mandatory = $true)][string]$DesiredProperties
    )

    $existing = @(Get-Customizer -Connection $Connection)

    if ($existing.Count -gt 1) {
        Write-Warn "Found $($existing.Count) custom actions for this component; collapsing to one."
    }
    elseif ($existing.Count -eq 1 -and $existing[0].ClientSideComponentProperties -eq $DesiredProperties) {
        Write-Skip "Custom action already up to date: $DesiredProperties"
        return
    }

    # There is no in-place update for ClientSideComponentProperties — remove, then re-add.
    foreach ($action in $existing) {
        Remove-PnPCustomAction -Identity $action.Id -Scope Site -Force -Connection $Connection
    }

    Write-Step "Adding the custom action: $DesiredProperties"
    Add-PnPCustomAction -Name $CustomActionName `
        -Title $CustomActionName `
        -Location $CustomActionLocation `
        -ClientSideComponentId $ComponentId `
        -ClientSideComponentProperties $DesiredProperties `
        -Scope Site `
        -Connection $Connection | Out-Null

    Write-Ok "Custom action $(if ($existing.Count) { 'updated' } else { 'added' })."
}

function Invoke-Deploy {
    param([Parameter(Mandatory = $true)][string]$Url)

    $package = Resolve-PackagePath
    $connection = Connect-Target -Url $Url

    try {
        if (Test-SiteCollectionAppCatalog -Connection $connection) {
            Write-Skip "Site collection app catalog already exists."
        }
        else {
            New-SiteCollectionAppCatalog -Url $Url -Connection $connection
        }

        Write-Step "Uploading $([IO.Path]::GetFileName($package)) to the site collection app catalog ..."
        $app = Add-PnPApp -Path $package -Scope Site -Overwrite -Publish -Connection $connection
        Write-Ok "Published $($app.Title) $($app.AppCatalogVersion)."

        # Re-read after publishing: Add-PnPApp's return value predates the install flags.
        $catalogApp = Get-SolutionApp -Connection $connection
        if (-not $catalogApp) {
            throw "The package is not in $Url's app catalog after publishing."
        }

        Install-OrUpgradeApp -Connection $connection -App $catalogApp

        Set-Customizer -Connection $connection -DesiredProperties (Get-DesiredProperties)
    }
    finally {
        Disconnect-Target -Connection $connection
    }
}

function Invoke-Remove {
    param([Parameter(Mandatory = $true)][string]$Url)

    $connection = Connect-Target -Url $Url

    try {
        $existing = @(Get-Customizer -Connection $connection)
        if ($existing.Count -eq 0) {
            Write-Skip "No custom action to remove."
        }
        else {
            foreach ($action in $existing) {
                Remove-PnPCustomAction -Identity $action.Id -Scope Site -Force -Connection $connection
            }
            Write-Ok "Removed $($existing.Count) custom action(s)."
        }

        if (-not (Test-SiteCollectionAppCatalog -Connection $connection)) {
            Write-Skip "Site has no app catalog; nothing else to remove."
            return
        }

        $catalogApp = Get-SolutionApp -Connection $connection
        if ($catalogApp) {
            # InstalledVersion is cleared by an overwrite-publish, so it cannot rule the
            # install out. Ask SharePoint to uninstall and treat "there is nothing there"
            # as success.
            try {
                Write-Step "Uninstalling the app from the site ..."
                Uninstall-PnPApp -Identity $catalogApp.Id -Scope Site -Connection $connection | Out-Null
                Write-Ok "App uninstalled."
            }
            catch {
                $uninstallError = Get-ErrorText -ErrorRecord $_
                if ($uninstallError -notmatch "not installed|does not exist|Cannot find|not found") { throw }
                Write-Skip "App is not installed on this site."
            }
        }

        if ($catalogApp) {
            Write-Step "Removing the package from the site collection app catalog ..."
            $removeArgs = Add-SupportedParameter -Command "Remove-PnPApp" `
                -Splat @{ Identity = $catalogApp.Id; Scope = "Site"; Connection = $connection } `
                -Optional @{ Force = $true }
            Remove-PnPApp @removeArgs
            Write-Ok "Package removed."
        }
        else {
            Write-Skip "Package is not in the site collection app catalog."
        }
    }
    finally {
        Disconnect-Target -Connection $connection
    }

    # Removing the catalog needs its own admin connection, so it runs after the site
    # connection is closed.
    if ($RemoveAppCatalog) {
        Remove-SiteCollectionAppCatalog -Url $Url
    }
}

function Invoke-Status {
    param([Parameter(Mandatory = $true)][string]$Url)

    $connection = Connect-Target -Url $Url

    try {
        if (Test-SiteCollectionAppCatalog -Connection $connection) {
            Write-Ok "Site collection app catalog: present"

            $catalogApp = Get-SolutionApp -Connection $connection
            if ($catalogApp) {
                Write-Host "  Package: $($catalogApp.Title) catalog=$($catalogApp.AppCatalogVersion) canUpgrade=$($catalogApp.CanUpgrade)" -ForegroundColor Gray

                if (Test-AppInstalled -App $catalogApp) {
                    Write-Host "  Installed version: $($catalogApp.InstalledVersion)" -ForegroundColor Gray
                }
                else {
                    # Reporting this as "not installed" would be a guess: SharePoint clears
                    # the field on every overwrite-publish, installed or not.
                    Write-Host "  Installed version: not reported (cleared by the last publish; not proof the app is absent)" -ForegroundColor Gray
                }
            }
            else {
                Write-Warn "Package: not in this site's app catalog"
            }
        }
        else {
            Write-Warn "Site collection app catalog: absent"
        }

        $existing = @(Get-Customizer -Connection $connection)
        if ($existing.Count -eq 0) {
            Write-Warn "Custom action: not installed"
        }
        else {
            foreach ($action in $existing) {
                Write-Ok "Custom action: $($action.Name) [$($action.Id)]"
                Write-Host "    $($action.ClientSideComponentProperties)" -ForegroundColor Gray
            }
        }
    }
    finally {
        Disconnect-Target -Connection $connection
    }
}

# Main execution
$module = Get-Module -ListAvailable -Name PnP.PowerShell | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) {
    throw "PnP.PowerShell is not installed. Install it with: Install-Module PnP.PowerShell -Scope CurrentUser"
}
if ($module.Version.Major -lt 2) {
    throw "PnP.PowerShell $($module.Version) is too old; this script needs 2.x or later."
}

$failed = @()

foreach ($url in $SiteUrl) {
    $url = $url.Trim().TrimEnd('/')
    if (-not $url) { continue }

    Write-Host ""
    Write-Host "$Action -> $url" -ForegroundColor White

    if (-not $PSCmdlet.ShouldProcess($url, $Action)) { continue }

    try {
        switch ($Action) {
            "Deploy" { Invoke-Deploy -Url $url }
            "Remove" { Invoke-Remove -Url $url }
            "Status" { Invoke-Status -Url $url }
        }
    }
    catch {
        # Keep going: one bad site should not strand the rest of the batch.
        $errorText = Get-ErrorText -ErrorRecord $_

        # A site in another tenant (or a typo) authenticates fine and then 401s on the
        # first real call, which reads as a permissions problem when it is a URL problem.
        if ($errorText -match "\(401\)|\(404\)|Unauthorized|Not Found") {
            $errorText += " — check that $url exists and belongs to the tenant you authenticated against."
        }

        Write-Host "  Failed: $errorText" -ForegroundColor Red
        $failed += $url
    }
}

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host "$Action failed on $($failed.Count) of $($SiteUrl.Count) site(s): $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "$Action completed on $($SiteUrl.Count) site(s)." -ForegroundColor Green

if ($Action -eq "Deploy") {
    Write-Host "If this is the first deployment, approve the API access request in SharePoint admin center > Advanced > API access, or run ./set.ps1." -ForegroundColor Yellow
}
