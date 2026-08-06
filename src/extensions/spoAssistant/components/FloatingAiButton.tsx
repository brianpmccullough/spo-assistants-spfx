import * as React from 'react';

import { AssistantApiClient } from '../services/AssistantApiClient';
import { IAssistantAction, IAssistantConfig } from '../models/IAssistantModels';
import { SparkleIcon } from './Icons';
import { useAiAssistant } from '../hooks/useAiAssistant';
import styles from './FloatingAiButton.module.scss';

export interface IFloatingAiButtonProps {
  config: IAssistantConfig;
  client: AssistantApiClient | undefined;
  /** Set when the customizer could not build a client, e.g. properties are missing. */
  configError?: string;
}

const TRIGGER_ID = 'spo-assistant-trigger';

type View = 'closed' | 'menu' | 'chat';

// Three load tiers: this file (+ Icons.tsx) is eager — cheap, no Fluent dependency, needed
// for the button to render at all. AiActionMenu and ChatSurface are each their own chunk,
// fetched only once the user actually opens them. ChatSurface is the one that matters most:
// it alone pulls in Fluent UI's TextField/IconButton/MessageBar/Spinner, which otherwise
// bloats every single page load in the tenant even for users who never open chat.
const AiActionMenu = React.lazy(() =>
  import(/* webpackChunkName: 'spo-assistant-menu' */ './AiActionMenu').then(module => ({
    default: module.AiActionMenu
  }))
);

const ChatSurface = React.lazy(() =>
  import(/* webpackChunkName: 'spo-assistant-chat' */ './chat/ChatSurface').then(module => ({
    default: module.ChatSurface
  }))
);

/** Suspense fallback while a chunk downloads. Deliberately plain CSS, no Fluent — using a
 * Fluent control here would defeat the point of keeping Fluent out of the eager bundle. */
const ChunkLoading: React.FC = () => (
  <div className={styles.loadingCard} role="status" aria-label="Loading…">
    <span className={styles.loadingSpinner} />
  </div>
);

export const FloatingAiButton: React.FC<IFloatingAiButtonProps> = ({ config, client, configError }) => {
  const [view, setView] = React.useState<View>('closed');
  const [chatSeedQuestion, setChatSeedQuestion] = React.useState<string | undefined>(undefined);
  const rootRef = React.useRef<HTMLDivElement>(null);
  const triggerRef = React.useRef<HTMLButtonElement>(null);

  const { connection, notice, dismissNotice, runAction } = useAiAssistant({
    client,
    enabled: view !== 'closed',
    configError
  });

  const close = React.useCallback(
    (returnFocus: boolean) => {
      setView('closed');
      setChatSeedQuestion(undefined);
      dismissNotice();
      if (returnFocus) {
        triggerRef.current?.focus();
      }
    },
    [dismissNotice]
  );

  const openChat = React.useCallback((seedQuestion?: string) => {
    setChatSeedQuestion(seedQuestion);
    setView('chat');
  }, []);

  // Dismiss on outside interaction. Pointerdown rather than click so the menu closes
  // before SharePoint's own surfaces react to the same gesture.
  React.useEffect(() => {
    if (view === 'closed') {
      return;
    }

    const onPointerDown = (event: MouseEvent): void => {
      if (!rootRef.current?.contains(event.target as Node)) {
        close(false);
      }
    };
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === 'Escape') {
        close(true);
      }
    };

    document.addEventListener('pointerdown', onPointerDown, true);
    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('pointerdown', onPointerDown, true);
      document.removeEventListener('keydown', onKeyDown, true);
    };
  }, [view, close]);

  const handleInvoke = (action: IAssistantAction): void => {
    if (action.id === 'openChat') {
      openChat();
      return;
    }
    runAction(action.id);
  };

  const handleAsk = (question: string): void => {
    openChat(question);
  };

  const themeVars = {
    '--spoAssistantFrom': config.theme.gradientFrom,
    '--spoAssistantVia': config.theme.gradientVia,
    '--spoAssistantTo': config.theme.gradientTo,
    '--spoAssistantAccent': config.theme.accent
  } as React.CSSProperties;

  return (
    <div className={styles.root} ref={rootRef} style={themeVars}>
      {view === 'menu' && (
        <React.Suspense fallback={<ChunkLoading />}>
          <AiActionMenu
            actions={config.actions}
            connection={connection}
            notice={notice}
            labelledBy={TRIGGER_ID}
            onInvoke={handleInvoke}
            onAsk={handleAsk}
            onRequestClose={() => close(true)}
          />
        </React.Suspense>
      )}

      {view === 'chat' && client && (
        <React.Suspense fallback={<ChunkLoading />}>
          <ChatSurface
            client={client}
            labelledBy={TRIGGER_ID}
            initialQuestion={chatSeedQuestion}
            onRequestClose={() => close(true)}
          />
        </React.Suspense>
      )}

      <button
        id={TRIGGER_ID}
        ref={triggerRef}
        type="button"
        className={styles.trigger}
        aria-label="Open AI assistant"
        aria-haspopup="menu"
        aria-expanded={view !== 'closed'}
        onClick={() => (view === 'closed' ? setView('menu') : close(true))}
      >
        <SparkleIcon className={styles.triggerIcon} size={22} />
      </button>

      {view === 'closed' && (
        <span className={styles.tooltip} aria-hidden={true}>
          Ask AI
        </span>
      )}
    </div>
  );
};
