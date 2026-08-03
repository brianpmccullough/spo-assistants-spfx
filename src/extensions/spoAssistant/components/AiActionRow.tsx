import * as React from 'react';

import { ActionIcon } from './Icons';
import { IAssistantAction } from '../models/IAssistantModels';
import styles from './AiActionMenu.module.scss';

export interface IAiActionRowProps {
  action: IAssistantAction;
  onInvoke: (action: IAssistantAction) => void;
  onKeyDown: (event: React.KeyboardEvent<HTMLButtonElement>) => void;
}

export const AiActionRow = React.forwardRef<HTMLButtonElement, IAiActionRowProps>(
  ({ action, onInvoke, onKeyDown }, ref) => (
    <button
      ref={ref}
      type="button"
      role="menuitem"
      className={styles.row}
      tabIndex={-1}
      onClick={() => onInvoke(action)}
      onKeyDown={onKeyDown}
    >
      <ActionIcon id={action.id} className={styles.rowIcon} size={17} />
      <span className={styles.rowLabel}>{action.label}</span>
    </button>
  )
);

AiActionRow.displayName = 'AiActionRow';
