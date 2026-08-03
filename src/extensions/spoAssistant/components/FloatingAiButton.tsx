import * as React from 'react';

import { AiActionMenu } from './AiActionMenu';
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

export const FloatingAiButton: React.FC<IFloatingAiButtonProps> = ({ config, client, configError }) => {
  const [isOpen, setIsOpen] = React.useState(false);
  const rootRef = React.useRef<HTMLDivElement>(null);
  const triggerRef = React.useRef<HTMLButtonElement>(null);

  const { connection, notice, dismissNotice, runAction, ask } = useAiAssistant({
    client,
    enabled: isOpen,
    configError,
    chatUrl: config.chatUrl
  });

  const close = React.useCallback(
    (returnFocus: boolean) => {
      setIsOpen(false);
      dismissNotice();
      if (returnFocus) {
        triggerRef.current?.focus();
      }
    },
    [dismissNotice]
  );

  // Dismiss on outside interaction. Pointerdown rather than click so the menu closes
  // before SharePoint's own surfaces react to the same gesture.
  React.useEffect(() => {
    if (!isOpen) {
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
  }, [isOpen, close]);

  const handleInvoke = (action: IAssistantAction): void => {
    runAction(action.id);
    // "Open chat" hands off to another surface, so the menu should get out of the way.
    if (action.id === 'openChat' && config.chatUrl) {
      close(false);
    }
  };

  const themeVars = {
    '--spoAssistantFrom': config.theme.gradientFrom,
    '--spoAssistantVia': config.theme.gradientVia,
    '--spoAssistantTo': config.theme.gradientTo,
    '--spoAssistantAccent': config.theme.accent
  } as React.CSSProperties;

  return (
    <div className={styles.root} ref={rootRef} style={themeVars}>
      {isOpen && (
        <AiActionMenu
          actions={config.actions}
          connection={connection}
          notice={notice}
          labelledBy={TRIGGER_ID}
          onInvoke={handleInvoke}
          onAsk={ask}
          onRequestClose={() => close(true)}
        />
      )}

      <button
        id={TRIGGER_ID}
        ref={triggerRef}
        type="button"
        className={styles.trigger}
        aria-label="Open AI assistant"
        aria-haspopup="menu"
        aria-expanded={isOpen}
        onClick={() => (isOpen ? close(true) : setIsOpen(true))}
      >
        <SparkleIcon className={styles.triggerIcon} size={22} />
      </button>

      {!isOpen && (
        <span className={styles.tooltip} aria-hidden={true}>
          Ask AI
        </span>
      )}
    </div>
  );
};
