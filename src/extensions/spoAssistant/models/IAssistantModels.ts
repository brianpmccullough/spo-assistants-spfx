/**
 * Identifiers for the actions the assistant menu can offer. Adding a new action means
 * adding an id here, an icon in `components/Icons.tsx`, and a branch in `useAiAssistant`.
 */
export type AssistantActionId = 'summarizePage' | 'findRelatedDocuments' | 'openChat';

export interface IAssistantAction {
  id: AssistantActionId;
  label: string;
  /** Actions after the divider are rendered as the escalation group at the bottom of the card. */
  belowDivider?: boolean;
}

/**
 * Placeholder brand colors. These are surfaced as customizer properties so a tenant can
 * restyle the button without a redeploy.
 */
export interface IAssistantTheme {
  gradientFrom: string;
  gradientVia: string;
  gradientTo: string;
  accent: string;
}

/**
 * Shape the SPFx client expects from `GET {apiBaseUrl}/me` on the site assistant API.
 * Field names mirror the API's `AuthenticatedUser` model, minus the access token —
 * the browser already holds its own token and the API should never echo one back.
 */
export interface ICurrentUser {
  objectId: string;
  displayName: string;
  email: string;
}

export type ConnectionStatus = 'idle' | 'loading' | 'connected' | 'error';

export interface IConnectionState {
  status: ConnectionStatus;
  user?: ICurrentUser;
  error?: string;
}

/** Runtime configuration read from the customizer's ClientSideComponentProperties. */
export interface IAssistantConfig {
  /** Origin of the site assistant API, e.g. `https://localhost:3000`. No trailing slash. */
  apiBaseUrl: string;
  /**
   * The API's Entra ID Application ID URI (or client ID). SPFx exchanges this for a
   * scoped access token via AadHttpClientFactory, so it must match an approved entry
   * in the tenant's API access page.
   */
  apiResourceUri: string;
  actions: IAssistantAction[];
  theme: IAssistantTheme;
}

/** A single turn in the in-product chat surface. Ephemeral, client-held (ADR-004) — never persisted. */
export interface IChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  timestamp: string;
}

export const DEFAULT_THEME: IAssistantTheme = {
  gradientFrom: '#036C70',
  gradientVia: '#5B3A9E',
  gradientTo: '#8E3B93',
  accent: '#5B3A9E'
};

export const DEFAULT_ACTIONS: IAssistantAction[] = [
  { id: 'summarizePage', label: 'Summarize this page' },
  { id: 'findRelatedDocuments', label: 'Find related documents' },
  { id: 'openChat', label: 'Open chat', belowDivider: true }
];
