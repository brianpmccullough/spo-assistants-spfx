# spo-assistants-spfx

## Summary

A tenant-wide floating AI assistant button for SharePoint Online, delivered as an SPFx
Application Customizer. It renders a gradient sparkle button pinned to the bottom-right of
every page; clicking it opens an upward action menu with quick actions, a divider, an
"Open chat" escalation row, and a persistent free-text input pinned to the bottom of the
card.

It is intended to read as *the* AI entry point for users who do not have Copilot licenses,
rather than as a secondary add-on.

Actions are backed by the
[SharePoint Site Assistant API](https://github.com/brianpmccullough/sharepoint-site-assistant-api),
a NestJS service secured with Microsoft Entra ID.

## Used SharePoint Framework Version

![version](https://img.shields.io/badge/version-1.23.2-green.svg)

## Applies to

- [SharePoint Framework](https://aka.ms/spfx)
- [Microsoft 365 tenant](https://docs.microsoft.com/sharepoint/dev/spfx/set-up-your-developer-tenant)

## Current state

Wired to the API:

- `GET {apiBaseUrl}/me` — fetched the first time the menu is opened, and shown as
  "Signed in as …" at the top of the card. This is the connectivity smoke test: a success
  proves the SPFx token request, the tenant API approval, CORS, and the API's JWT
  validation all line up.

Not yet wired — these render a plain "not connected yet" notice rather than failing
silently:

- Summarize this page
- Find related documents
- The free-text ask input
- Open chat (opens `chatUrl` in a new tab if that property is set)

## Configuration

All settings come from the custom action's `ClientSideComponentProperties`, so they can be
changed per tenant or per site without a redeploy.

| Property         | Required | Description                                                                          |
| ---------------- | -------- | ------------------------------------------------------------------------------------ |
| `apiBaseUrl`     | Yes      | Origin of the site assistant API, e.g. `https://localhost:3000`. No trailing slash.   |
| `apiResourceUri` | Yes      | The API's Entra ID Application ID URI or client ID, e.g. `api://<client-id>`.         |
| `chatUrl`        | No       | Deep link used by the "Open chat" action until an in-product chat surface exists.     |
| `actions`        | No       | Overrides the menu list. Defaults to the three actions above.                         |
| `theme`          | No       | `gradientFrom` / `gradientVia` / `gradientTo` / `accent` hex values.                  |

If `apiBaseUrl` or `apiResourceUri` is missing, the button still renders and the menu shows
a configuration message instead of throwing on every page in the tenant.

### Serve configurations

`config/serve.json` defines which API the local workbench/debug session talks to:

| Configuration           | `apiBaseUrl`                                                                         | Command                 |
| ----------------------- | ------------------------------------------------------------------------------------ | ----------------------- |
| `default` / `spoAssistant` | `http://localhost:3000` — API running locally                                       | `pnpm start`            |
| `spoAssistantContainer` | `https://container-app-spo-assistants.agreeablesand-e9283835.swedencentral.azurecontainerapps.io` — deployed Azure Container App | `pnpm start:container`  |

`pnpm start:container` is just `heft start --clean --serve-config spoAssistantContainer`.
The container app's CORS must allow the debug origin (`https://<tenant>.sharepoint.com`)
the same way the local API does.

Placeholders to replace before deploying:

- `sharepoint/assets/elements.xml` — `REPLACE-WITH-API-HOST`, the origin the deployed API
  is reachable at. `config/serve.json` already points at `https://localhost:3000` for local
  debugging, and both files now carry the real `apiResourceUri`.
- `config/package-solution.json` — `REPLACE-WITH-API-APP-REGISTRATION-DISPLAY-NAME` under
  `webApiPermissionRequests`. This must match the **display name** of the API's app
  registration, and the scope must be one the registration exposes.

### Entra ID setup

1. In the API's app registration, expose an API with an Application ID URI
   (`api://<client-id>`) and a delegated scope (`user_impersonation` by default here).
2. Deploy the `.sppkg`, then approve the pending request in SharePoint admin center >
   Advanced > API access. Without this approval `AadHttpClientFactory` cannot issue tokens.
3. The API's CORS regex is driven by its `TENANT_NAME` env var and already allows
   `https://<tenant>.sharepoint.com`.

### Scripts

`scripts/` holds PowerShell helpers for the pieces that cannot be done from the build:

| Script          | Purpose                                                                       |
| --------------- | ----------------------------------------------------------------------------- |
| `get.ps1`       | Lists the delegated scopes already granted to SPFx on the API. Microsoft.Graph. |
| `set.ps1`       | Grants a scope (default `user_impersonation`) — the scripted equivalent of approving the request in SharePoint admin center > Advanced > API access. |
| `script.ps1`    | `-Action Deploy \| Install \| Update \| Remove \| Status` for the app catalog package and the per-site custom action. PnP.PowerShell. |

The API's client ID, the tenant ID, and the solution/component IDs are hardcoded as
parameter defaults at the top of each script — override them on the command line when
targeting something else. Local `pnpm start` runs are unaffected; those read
`config/serve.json`.

```powershell
cd scripts
./set.ps1                                                    # grant user_impersonation
./get.ps1                                                    # verify
./script.ps1 -Action Deploy -PnPClientId <id> -TenantAdminUrl https://contoso-admin.sharepoint.com
./script.ps1 -Action Install -PnPClientId <id> -SiteUrl https://contoso.sharepoint.com/sites/hr
./script.ps1 -Action Update -PnPClientId <id> -SiteUrl <site> -ApiBaseUrl https://api.contoso.com
```

`-PnPClientId` is required — an app registration for PnP PowerShell's interactive sign-in,
separate from the API's.

### API contract

The client expects `GET /me` to return JSON matching the API's `AuthenticatedUser` model,
minus the access token — the browser holds its own token and the API should never echo one
back:

```json
{
  "objectId": "00000000-0000-0000-0000-000000000000",
  "displayName": "Jane Doe",
  "email": "jane@contoso.com"
}
```

Raw Entra ID claim names (`oid`, `name`, `upn`, `preferred_username`) are also accepted.
This route does not exist in the API yet.

## Structure

```
src/extensions/spoAssistant/
  SpoAssistantApplicationCustomizer.ts   renders into the Bottom placeholder
  components/
    FloatingAiButton.tsx                 trigger button, owns open/closed state
    AiActionMenu.tsx                     the menu card and its keyboard handling
    AiActionRow.tsx                      a single icon + label row
    AskInput.tsx                         the pinned free-text input
    Icons.tsx                            inline SVGs
  hooks/useAiAssistant.ts                connection state and action dispatch
  services/AssistantApiClient.ts         AadHttpClient wrapper over the API
  models/IAssistantModels.ts             config, theme, and action types
```

The React tree is hosted in SharePoint's `PlaceholderName.Bottom` via
`context.placeholderProvider.tryCreateContent`, subscribed to `changedEvent` so it survives
client-side navigation. The button itself is taken out of flow with `position: fixed` in
CSS, so the placeholder contributes no page height.

### Behavior notes

- `z-index: 2147483000` — high enough to clear SharePoint's command bar and flyouts, well
  below the browser maximum. Worth re-checking against the native Copilot panel if that is
  ever enabled in the tenant.
- Because the host lives inside SharePoint's DOM rather than on `document.body`, a future
  SharePoint change that puts a `transform`, `filter`, or `contain` on an ancestor of the
  Bottom placeholder would re-anchor `position: fixed` to that ancestor. Worth a look if
  the button ever stops tracking the viewport.
- The API is not contacted until the user first opens the menu. This customizer runs on
  every page in the tenant, so an eager call would be a tenant-wide request per page view.
- Accessibility: `aria-label` on the icon-only trigger, `aria-haspopup`/`aria-expanded`,
  `role="menu"`/`role="menuitem"` rows with arrow-key/Home/End roving focus, Escape closes
  and returns focus to the trigger, outside pointerdown closes. The ask input sits outside
  the `role="menu"` group so it is not announced as a menu item.
- No idle animation on the trigger — deliberately calm. The menu's open transition is gated
  behind `prefers-reduced-motion`.

## Minimal Path to Awesome

- Clone this repository
- Ensure that you are at the solution folder
- In the command line run:
  - `pnpm install`
  - `pnpm start` (or `npx heft start`)

`pnpm-workspace.yaml` sets `publicHoistPattern: ["*"]` — the SPFx build rig resolves many
packages by flat path and fails without it.

Note that `@types/react` and `@types/react-dom` are pinned to 17.0.93 / 17.0.26 to match
the copies the SPFx rig already brings in. Installing different patch versions produces two
distinct `ReactElement` types and `ReactDOM.render` stops type-checking.

Other build commands can be listed using `npx heft --help`.

## Disclaimer

**THIS CODE IS PROVIDED _AS IS_ WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.**

## References

- [Getting started with SharePoint Framework](https://docs.microsoft.com/sharepoint/dev/spfx/set-up-your-developer-tenant)
- [Connect to Azure AD-secured APIs in SharePoint Framework solutions](https://learn.microsoft.com/sharepoint/dev/spfx/use-aadhttpclient)
- [Microsoft 365 Patterns and Practices](https://aka.ms/m365pnp)
- [Heft Documentation](https://heft.rushstack.io/)
