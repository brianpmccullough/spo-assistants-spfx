import { AadHttpClient, AadHttpClientFactory, HttpClientResponse } from '@microsoft/sp-http';

import { ICurrentUser } from '../models/IAssistantModels';

/**
 * Thin wrapper over the Entra ID-secured site assistant API
 * (https://github.com/brianpmccullough/sharepoint-site-assistant-api).
 *
 * SPFx obtains a bearer token for `resourceUri` through AadHttpClientFactory; the API
 * validates it with passport-azure-ad. Nothing here handles tokens directly.
 */
export class AssistantApiClient {
  private _client: Promise<AadHttpClient> | undefined;

  public constructor(
    private readonly _factory: AadHttpClientFactory,
    private readonly _baseUrl: string,
    private readonly _resourceUri: string
  ) {}

  /**
   * Fetches the caller's identity as the API sees it. This is the connectivity smoke
   * test: a success proves the SPFx token request, the tenant API approval, CORS, and
   * the API's JWT validation all line up.
   */
  public async getCurrentUser(): Promise<ICurrentUser> {
    const response = await this._get('/me');

    if (!response.ok) {
      throw new Error(await this._describeFailure(response));
    }

    return this._toCurrentUser(await response.json());
  }

  private async _get(path: string): Promise<HttpClientResponse> {
    const client = await this._getClient();
    return client.get(`${this._baseUrl}${path}`, AadHttpClient.configurations.v1);
  }

  private async _getClient(): Promise<AadHttpClient> {
    // Cache the promise, not the resolved client, so concurrent callers share one token request.
    if (!this._client) {
      this._client = this._factory.getClient(this._resourceUri);
    }
    return this._client;
  }

  /**
   * The API returns Nest's `{ statusCode, message }` envelope for handled errors, but a
   * gateway or CORS failure can produce anything. Fall back to the status line.
   */
  private async _describeFailure(response: HttpClientResponse): Promise<string> {
    let detail: string | undefined;

    try {
      const body: { message?: string | string[] } = await response.json();
      detail = Array.isArray(body.message) ? body.message.join(', ') : body.message;
    } catch {
      detail = undefined;
    }

    if (response.status === 401 || response.status === 403) {
      return detail ?? 'You are not authorized to use the assistant.';
    }

    return detail ?? `Request failed (HTTP ${response.status}).`;
  }

  /** Tolerates either the API's own field names or raw Entra ID claim names. */
  private _toCurrentUser(body: Record<string, string | undefined>): ICurrentUser {
    return {
      objectId: body.objectId ?? body.oid ?? '',
      displayName: body.displayName ?? body.name ?? 'Unknown user',
      email: body.email ?? body.upn ?? body.preferred_username ?? ''
    };
  }
}
