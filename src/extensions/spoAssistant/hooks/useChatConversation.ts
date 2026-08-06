import { useCallback, useEffect, useRef, useState } from 'react';

import { AssistantApiClient } from '../services/AssistantApiClient';
import { IChatMessage } from '../models/IAssistantModels';

export interface IUseChatConversation {
  messages: IChatMessage[];
  isSending: boolean;
  error: string | undefined;
  sendMessage: (text: string) => void;
}

function newMessage(role: IChatMessage['role'], text: string): IChatMessage {
  return { id: crypto.randomUUID(), role, text, timestamp: new Date().toISOString() };
}

/**
 * Owns the conversation transcript for one open chat surface. Deliberately in-memory
 * only (ADR-004): the transcript is client-held and disappears when the surface closes
 * or the page navigates — nothing here reads or writes any storage.
 */
export function useChatConversation(client: AssistantApiClient | undefined): IUseChatConversation {
  const [messages, setMessages] = useState<IChatMessage[]>([]);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | undefined>(undefined);
  const isMounted = useRef(true);

  useEffect(() => {
    return () => {
      isMounted.current = false;
    };
  }, []);

  const sendMessage = useCallback(
    (text: string): void => {
      const trimmed = text.trim();
      if (!trimmed || !client) {
        return;
      }

      setMessages(previous => [...previous, newMessage('user', trimmed)]);
      setIsSending(true);
      setError(undefined);

      // `Promise.prototype.finally` needs an ES2018+ lib target that SPFx's tsconfig
      // doesn't set, so cleanup uses try/finally (a language construct, not a Promise
      // method) inside this async helper instead of a `.finally()` chain.
      const run = async (): Promise<void> => {
        try {
          const response = await client.chat(trimmed);
          if (!isMounted.current) {
            return;
          }
          // The API echoes { message, serverDateTime, ... } today; fall back to a
          // generic acknowledgement if a future response shape omits `message`.
          const replyText =
            typeof response.message === 'string' ? `You said: "${response.message}"` : 'Message received.';
          const serverDateTime =
            typeof response.serverDateTime === 'string' ? ` (server time: ${response.serverDateTime})` : '';

          setMessages(previous => [...previous, newMessage('assistant', `${replyText}${serverDateTime}`)]);
        } catch (sendError) {
          if (isMounted.current) {
            setError((sendError as Error).message);
          }
        } finally {
          if (isMounted.current) {
            setIsSending(false);
          }
        }
      };

      run().catch(() => undefined);
    },
    [client]
  );

  return { messages, isSending, error, sendMessage };
}
