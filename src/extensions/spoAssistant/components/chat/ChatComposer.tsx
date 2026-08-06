import * as React from 'react';

import { IconButton, ITextField, TextField } from '@fluentui/react';

import styles from './ChatSurface.module.scss';

export interface IChatComposerProps {
  disabled: boolean;
  onSend: (text: string) => void;
}

export const ChatComposer: React.FC<IChatComposerProps> = ({ disabled, onSend }) => {
  const [value, setValue] = React.useState('');
  const canSend = !disabled && value.trim().length > 0;
  const textFieldRef = React.useRef<ITextField>(null);
  const wasDisabled = React.useRef(disabled);

  // Neither React nor the browser restores focus when a disabled input re-enables, so
  // without this the field goes dead after every send and the user has to click back in
  // before they can type the next message.
  React.useEffect(() => {
    if (wasDisabled.current && !disabled) {
      textFieldRef.current?.focus();
    }
    wasDisabled.current = disabled;
  }, [disabled]);

  const submit = (): void => {
    if (!canSend) {
      return;
    }
    onSend(value);
    setValue('');
  };

  return (
    <div className={styles.composerRow}>
      <TextField
        componentRef={textFieldRef}
        className={styles.composerField}
        placeholder="Ask a question about this site"
        aria-label="Chat message"
        value={value}
        disabled={disabled}
        onChange={(_event, newValue) => setValue(newValue ?? '')}
        onKeyDown={event => {
          if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            submit();
          }
        }}
      />
      <IconButton iconProps={{ iconName: 'Send' }} ariaLabel="Send" disabled={!canSend} onClick={submit} />
    </div>
  );
};
