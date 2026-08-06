import * as React from 'react';

import { Text } from '@fluentui/react';

import { IChatMessage } from '../../models/IAssistantModels';
import styles from './ChatSurface.module.scss';

export interface IChatMessageBubbleProps {
  message: IChatMessage;
}

export const ChatMessageBubble: React.FC<IChatMessageBubbleProps> = ({ message }) => {
  const isUser = message.role === 'user';

  return (
    <div className={`${styles.bubbleRow} ${isUser ? styles.bubbleRowUser : styles.bubbleRowAssistant}`}>
      <Text as="div" className={`${styles.bubble} ${isUser ? styles.bubbleUser : styles.bubbleAssistant}`}>
        {message.text}
      </Text>
    </div>
  );
};
