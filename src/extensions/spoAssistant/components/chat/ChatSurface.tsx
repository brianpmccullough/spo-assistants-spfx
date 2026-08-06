import * as React from 'react';

import { IconButton, MessageBar, MessageBarType, Text } from '@fluentui/react';

import { AssistantApiClient } from '../../services/AssistantApiClient';
import { ChatComposer } from './ChatComposer';
import { ChatMessageList } from './ChatMessageList';
import { useChatConversation } from '../../hooks/useChatConversation';
import styles from './ChatSurface.module.scss';

export interface IChatSurfaceProps {
  client: AssistantApiClient;
  labelledBy: string;
  /** A question handed off from the action menu's Ask field, sent automatically on open. */
  initialQuestion?: string;
  onRequestClose: () => void;
}

export const ChatSurface: React.FC<IChatSurfaceProps> = ({
  client,
  labelledBy,
  initialQuestion,
  onRequestClose
}) => {
  const { messages, isSending, error, sendMessage } = useChatConversation(client);

  // A fresh ChatSurface instance is created each time the surface opens, so this only
  // needs to guard against React's own double-invoke in development, not real re-opens.
  const hasSentInitial = React.useRef(false);
  React.useEffect(() => {
    if (initialQuestion && !hasSentInitial.current) {
      hasSentInitial.current = true;
      sendMessage(initialQuestion);
    }
  }, [initialQuestion, sendMessage]);

  return (
    <div className={styles.card} role="dialog" aria-labelledby={labelledBy}>
      <div className={styles.header}>
        <Text className={styles.headerTitle}>Site Assistant</Text>
        <IconButton iconProps={{ iconName: 'Cancel' }} ariaLabel="Close chat" onClick={onRequestClose} />
      </div>

      <ChatMessageList messages={messages} isSending={isSending} />

      {error && (
        <MessageBar messageBarType={MessageBarType.error} className={styles.errorRow}>
          {error}
        </MessageBar>
      )}

      <ChatComposer disabled={isSending} onSend={sendMessage} />
    </div>
  );
};
