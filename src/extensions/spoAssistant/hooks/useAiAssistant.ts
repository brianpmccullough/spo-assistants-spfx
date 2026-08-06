import { useCallback, useEffect, useRef, useState } from 'react';

import { AssistantApiClient } from '../services/AssistantApiClient';
import { AssistantActionId, IConnectionState } from '../models/IAssistantModels';

export interface IUseAiAssistant {
  connection: IConnectionState;
  /** Transient message shown at the top of the menu card after an action runs. */
  notice: string | undefined;
  dismissNotice: () => void;
  runAction: (id: AssistantActionId) => void;
}

export interface IUseAiAssistantOptions {
  client: AssistantApiClient | undefined;
  /**
   * Gates the identity call. This customizer runs on every page in the tenant, so the
   * API is not contacted until the user actually opens the assistant.
   */
  enabled: boolean;
  /** Reason the client could not be constructed, e.g. missing configuration. */
  configError?: string;
}

export function useAiAssistant(options: IUseAiAssistantOptions): IUseAiAssistant {
  const { client, enabled, configError } = options;

  const [connection, setConnection] = useState<IConnectionState>({ status: 'idle' });
  const [notice, setNotice] = useState<string | undefined>(undefined);
  const isMounted = useRef(true);

  useEffect(() => {
    return () => {
      isMounted.current = false;
    };
  }, []);

  useEffect(() => {
    if (!enabled) {
      return;
    }
    if (configError) {
      setConnection({ status: 'error', error: configError });
      return;
    }
    // A resolved connection is kept for the life of the page; reopening should not refetch.
    if (!client || connection.status !== 'idle') {
      return;
    }

    setConnection({ status: 'loading' });

    client
      .getCurrentUser()
      .then(user => {
        if (isMounted.current) {
          setConnection({ status: 'connected', user });
        }
      })
      .catch((error: Error) => {
        if (isMounted.current) {
          setConnection({ status: 'error', error: error.message });
        }
      });
  }, [client, enabled, configError, connection.status]);

  const dismissNotice = useCallback(() => setNotice(undefined), []);

  const runAction = useCallback((id: AssistantActionId) => {
    // `openChat` is intercepted by FloatingAiButton before this ever runs (it opens the
    // in-product chat surface directly). Only the still-unimplemented actions land here.
    setNotice('This action is not connected to the assistant API yet.');
  }, []);

  return { connection, notice, dismissNotice, runAction };
}
