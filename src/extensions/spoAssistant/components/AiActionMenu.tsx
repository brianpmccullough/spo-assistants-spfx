import * as React from 'react';

import { AiActionRow } from './AiActionRow';
import { AskInput } from './AskInput';
import { IAssistantAction, IConnectionState } from '../models/IAssistantModels';
import styles from './AiActionMenu.module.scss';

export interface IAiActionMenuProps {
  actions: IAssistantAction[];
  connection: IConnectionState;
  notice: string | undefined;
  labelledBy: string;
  onInvoke: (action: IAssistantAction) => void;
  onAsk: (question: string) => void;
  onRequestClose: () => void;
}

const ConnectionBanner: React.FC<{ connection: IConnectionState; notice: string | undefined }> = ({
  connection,
  notice
}) => {
  // A notice is the result of something the user just did, so it outranks steady-state status.
  if (notice) {
    return (
      <div className={styles.banner} role="status">
        {notice}
      </div>
    );
  }

  switch (connection.status) {
    case 'loading':
      return (
        <div className={styles.banner} role="status">
          Connecting to the assistant…
        </div>
      );
    case 'connected':
      return (
        <div className={styles.banner} role="status">
          Signed in as {connection.user?.displayName}
        </div>
      );
    case 'error':
      return (
        <div className={`${styles.banner} ${styles.bannerError}`} role="alert">
          {connection.error}
        </div>
      );
    default:
      return null;
  }
};

export const AiActionMenu: React.FC<IAiActionMenuProps> = ({
  actions,
  connection,
  notice,
  labelledBy,
  onInvoke,
  onAsk,
  onRequestClose
}) => {
  const rowRefs = React.useRef<(HTMLButtonElement | null)[]>([]);

  React.useEffect(() => {
    rowRefs.current[0]?.focus();
  }, []);

  const focusRow = (index: number): void => {
    const rows = rowRefs.current.filter(Boolean) as HTMLButtonElement[];
    if (rows.length === 0) {
      return;
    }
    // Wrap in both directions so arrow keys cycle rather than dead-ending.
    rows[(index + rows.length) % rows.length].focus();
  };

  const handleRowKeyDown = (
    index: number
  ): ((event: React.KeyboardEvent<HTMLButtonElement>) => void) => (event): void => {
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        focusRow(index + 1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        focusRow(index - 1);
        break;
      case 'Home':
        event.preventDefault();
        focusRow(0);
        break;
      case 'End':
        event.preventDefault();
        focusRow(rowRefs.current.length - 1);
        break;
      default:
        break;
    }
  };

  const above = actions.filter(action => !action.belowDivider);
  const below = actions.filter(action => action.belowDivider);

  const renderRows = (group: IAssistantAction[], offset: number): JSX.Element[] =>
    group.map((action, index) => (
      <AiActionRow
        key={action.id}
        action={action}
        ref={element => {
          rowRefs.current[offset + index] = element;
        }}
        onInvoke={onInvoke}
        onKeyDown={handleRowKeyDown(offset + index)}
      />
    ));

  return (
    <div
      className={styles.card}
      onKeyDown={event => {
        if (event.key === 'Escape') {
          event.stopPropagation();
          onRequestClose();
        }
      }}
    >
      <ConnectionBanner connection={connection} notice={notice} />

      <div role="menu" aria-labelledby={labelledBy} className={styles.menu}>
        {renderRows(above, 0)}
        {below.length > 0 && <hr className={styles.divider} />}
        {renderRows(below, above.length)}
      </div>

      <AskInput placeholder="Ask a question about this site" onAsk={onAsk} />
    </div>
  );
};
