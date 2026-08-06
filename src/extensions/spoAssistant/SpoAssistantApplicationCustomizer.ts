import * as React from 'react';
import * as ReactDom from 'react-dom';

import {
  BaseApplicationCustomizer,
  PlaceholderContent,
  PlaceholderName
} from '@microsoft/sp-application-base';
import { Log } from '@microsoft/sp-core-library';
import { initializeIcons } from '@fluentui/react/lib/Icons';

import * as strings from 'SpoAssistantApplicationCustomizerStrings';

import { AssistantApiClient } from './services/AssistantApiClient';
import { FloatingAiButton, IFloatingAiButtonProps } from './components/FloatingAiButton';
import {
  DEFAULT_ACTIONS,
  DEFAULT_THEME,
  IAssistantAction,
  IAssistantConfig,
  IAssistantTheme
} from './models/IAssistantModels';

const LOG_SOURCE: string = 'SpoAssistantApplicationCustomizer';

/**
 * Deserialized from the custom action's ClientSideComponentProperties. Everything is
 * optional so a misconfigured deployment degrades to a visible message rather than a
 * crash on every page in the tenant.
 */
export interface ISpoAssistantApplicationCustomizerProperties {
  /** Origin of the site assistant API, e.g. `https://localhost:3000`. */
  apiBaseUrl?: string;
  /** The API's Entra ID Application ID URI or client ID. */
  apiResourceUri?: string;
  actions?: IAssistantAction[];
  theme?: Partial<IAssistantTheme>;
}

/**
 * Renders a floating assistant button in the bottom-right corner of every page.
 *
 * The React tree is hosted in the Bottom placeholder. That element sits at the end of the
 * page in SharePoint's own DOM, which is where a page-level chrome element belongs; the
 * button itself is taken out of flow with `position: fixed` in CSS, so the placeholder
 * contributes no height.
 */
export default class SpoAssistantApplicationCustomizer extends BaseApplicationCustomizer<ISpoAssistantApplicationCustomizerProperties> {
  private _bottomPlaceholder: PlaceholderContent | undefined;

  public onInit(): Promise<void> {
    Log.info(LOG_SOURCE, `Initialized ${strings.Title}`);

    // Registers the Fluent icon font once per page load. Required before any Fluent
    // icon-based control (IconButton, Spinner, etc.) renders, or glyphs show as blanks.
    initializeIcons();

    // Placeholders are not guaranteed to exist yet at onInit, and they are recreated as
    // the user navigates between pages, so render on every change rather than just once.
    this.context.placeholderProvider.changedEvent.add(this, this._renderPlaceholders);
    this._renderPlaceholders();

    return Promise.resolve();
  }

  private _renderPlaceholders(): void {
    if (this._bottomPlaceholder) {
      return;
    }

    this._bottomPlaceholder = this.context.placeholderProvider.tryCreateContent(
      PlaceholderName.Bottom,
      { onDispose: this._onPlaceholderDispose.bind(this) }
    );

    if (!this._bottomPlaceholder) {
      Log.error(LOG_SOURCE, new Error('Could not find the Bottom placeholder.'));
      return;
    }

    if (!this._bottomPlaceholder.domElement) {
      return;
    }

    const element: React.ReactElement<IFloatingAiButtonProps> = React.createElement(
      FloatingAiButton,
      this._buildProps()
    );

    ReactDom.render(element, this._bottomPlaceholder.domElement);
  }

  private _onPlaceholderDispose(): void {
    Log.info(LOG_SOURCE, 'Disposing the assistant placeholder.');

    if (this._bottomPlaceholder?.domElement) {
      ReactDom.unmountComponentAtNode(this._bottomPlaceholder.domElement);
    }

    // Clear the handle so the next changedEvent recreates the placeholder.
    this._bottomPlaceholder = undefined;
  }

  private _buildProps(): IFloatingAiButtonProps {
    const { apiBaseUrl, apiResourceUri, actions, theme } = this.properties;

    const config: IAssistantConfig = {
      // A trailing slash here would produce `//me` against the API.
      apiBaseUrl: (apiBaseUrl ?? '').replace(/\/+$/, ''),
      apiResourceUri: apiResourceUri ?? '',
      actions: actions && actions.length > 0 ? actions : DEFAULT_ACTIONS,
      theme: { ...DEFAULT_THEME, ...theme }
    };

    if (!config.apiBaseUrl || !config.apiResourceUri) {
      const configError =
        'The assistant is not configured. Set apiBaseUrl and apiResourceUri in the extension properties.';
      Log.warn(LOG_SOURCE, configError);
      return { config, client: undefined, configError };
    }

    return {
      config,
      client: new AssistantApiClient(
        this.context.aadHttpClientFactory,
        config.apiBaseUrl,
        config.apiResourceUri
      )
    };
  }
}
