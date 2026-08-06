import * as React from 'react';

import { Spinner, SpinnerSize } from '@fluentui/react';

import { ChatMessageBubble } from './ChatMessageBubble';
import { IChatMessage } from '../../models/IAssistantModels';
import styles from './ChatSurface.module.scss';

export interface IChatMessageListProps {
  messages: IChatMessage[];
  isSending: boolean;
}

export const ChatMessageList: React.FC<IChatMessageListProps> = ({ messages, isSending }) => {
  const endRef = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' });
  }, [messages.length, isSending]);

  if (messages.length === 0 && !isSending) {
    return (
      <div className={styles.messageList}>
        <div className={styles.emptyState}>Ask the site assistant a question to get started.</div>
      </div>
    );
  }

  return (
    <div className={styles.messageList}>
      {messages.map(message => (
        <ChatMessageBubble key={message.id} message={message} />
      ))}
      {isSending && (
        <div className={styles.typingRow}>
          <Spinner size={SpinnerSize.small} label="Thinking…" labelPosition="right" />
        </div>
      )}
      <div ref={endRef} />
    </div>
  );
};
