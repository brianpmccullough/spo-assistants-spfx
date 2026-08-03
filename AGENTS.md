# AGENTS.md

Guidance for AI coding agents working in this repo.

## What this is

SPFx 1.23.2 Application Customizer that renders a floating AI assistant button on every page
of a SharePoint Online tenant. The backend it talks to is the sibling repo
[`spo-assistants-api`](https://github.com/brianpmccullough/spo-assistants-api) (NestJS,
Entra ID-secured).

**That repo owns all technical documentation for both.** Architecture, ADRs, and env
variable reference live in its `/docs`. Don't start a `/docs` tree here — put reference
material there, in the same PR as the code that changes it. `README.md` here stays a
component-level overview.

## Non-negotiable rules

These match the API repo; keep them aligned.

- Every default value (config defaults, parameter defaults, fallback constants) is defined
  in exactly one place. Never re-type a default in a test, a mock, a second module, or a
  doc's prose — derive it from the source that owns it. Docs may *state* a default; code
  must never duplicate one.
- Before writing a helper, search for something that already does it or is close enough to
  generalize.
- Name helpers for what they generically *do*, not for the one call site that prompted
  them. Prefer a parameter over hardcoding today's single case.

## Build and validate

Package manager is **pnpm**. Node must satisfy `>=22.14.0 <23.0.0`.

```bash
pnpm install
pnpm start          # heft start --clean, serves on 4321 using config/serve.json
pnpm run build      # heft test --clean --production && heft package-solution --production
npx heft --help     # everything else
```

After any editing session, run `pnpm run build` — it type-checks, lints via the SPFx rig,
and produces the `.sppkg`. There is no separate `lint` or `test` script and no test files
yet; if you add tests, Heft picks them up through `heft test`.

`pnpm-workspace.yaml` sets `publicHoistPattern: ["*"]`. The SPFx rig resolves packages by
flat path and the build fails without it — don't remove it.

`@types/react` / `@types/react-dom` are pinned to 17.0.93 / 17.0.26 to match the copies the
rig brings in. Different patch versions produce two distinct `ReactElement` types and
`ReactDOM.render` stops type-checking.

## Configuration and identity

Runtime settings come from the custom action's `ClientSideComponentProperties`
(`apiBaseUrl`, `apiResourceUri`, optional `chatUrl`, `actions`, `theme`), so they change per
site without a redeploy. Nothing is read from a `.env` — this repo has none, and the
PowerShell scripts in `scripts/` carry their values as parameter defaults.

Four IDs must stay in sync when any of them changes:

| Value | Source of truth | Also appears in |
| --- | --- | --- |
| Solution / product ID | `config/package-solution.json` | `scripts/script.ps1` `$AppId` |
| Component ID | `SpoAssistantApplicationCustomizer.manifest.json` | `config/serve.json`, `sharepoint/assets/*.xml`, `scripts/script.ps1` `$ComponentId` |
| Custom action title | `sharepoint/assets/elements.xml` | `scripts/script.ps1` `$CustomActionTitle` |
| API client ID | the API's Entra app registration | `config/serve.json`, `sharepoint/assets/elements.xml`, `scripts/{get,set,script}.ps1` |

`config/serve.json` configures `pnpm start` only. `sharepoint/assets/elements.xml`
configures the deployed package. **Editing one does not affect the other, and neither
affects sites already provisioned** — a deployed `.sppkg` carries its own copy of the
properties, so a stale package keeps serving stale values until it is rebuilt and
redeployed. Diagnose against the artifact (`unzip -p *.sppkg`), not the working tree.

## Style

Match the surrounding code. Comments here explain *why* a non-obvious constraint exists
(z-index choice, placeholder re-render, trailing-slash trim) rather than restating the
statement below them — keep that bar. Existing files use SPFx conventions: `I`-prefixed
interfaces, `_`-prefixed private members, SCSS modules.
