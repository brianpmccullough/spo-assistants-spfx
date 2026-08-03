import * as React from 'react';

import { SendIcon } from './Icons';
import styles from './AiActionMenu.module.scss';

export interface IAskInputProps {
  placeholder: string;
  onAsk: (question: string) => void;
}

/**
 * The free-text field pinned to the bottom of the menu card. It is a peer of the action
 * rows rather than one of them: it stays interactive while other rows are hovered, and
 * it is deliberately outside the `role="menu"` group so screen readers do not announce
 * a textbox as a menu item.
 */
export const AskInput: React.FC<IAskInputProps> = ({ placeholder, onAsk }) => {
  const [value, setValue] = React.useState('');
  const canSend = value.trim().length > 0;

  const submit = (): void => {
    if (!canSend) {
      return;
    }
    onAsk(value);
    setValue('');
  };

  return (
    <div className={styles.askRow}>
      <input
        type="text"
        className={styles.askInput}
        placeholder={placeholder}
        aria-label={placeholder}
        value={value}
        onChange={event => setValue(event.target.value)}
        onKeyDown={event => {
          // Let Escape bubble to the card so it closes the menu as it would anywhere else.
          if (event.key === 'Enter') {
            event.preventDefault();
            submit();
          }
        }}
      />
      <button
        type="button"
        className={styles.askSend}
        aria-label="Send"
        disabled={!canSend}
        onClick={submit}
      >
        <SendIcon size={16} />
      </button>
    </div>
  );
};
