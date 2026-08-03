import * as React from 'react';

import { AssistantActionId } from '../models/IAssistantModels';

interface IIconProps {
  className?: string;
  size?: number;
}

function svgProps(size: number, className?: string): React.SVGProps<SVGSVGElement> {
  return {
    className,
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    focusable: false,
    'aria-hidden': true
  };
}

/** The 4-point sparkle used as the assistant's mark. */
export const SparkleIcon: React.FC<IIconProps> = ({ className, size = 22 }) => (
  <svg {...svgProps(size, className)} fill="currentColor">
    <path d="M12 1.5l2.35 7.15L21.5 11l-7.15 2.35L12 20.5l-2.35-7.15L2.5 11l7.15-2.35L12 1.5z" />
  </svg>
);

const SummarizeIcon: React.FC<IIconProps> = ({ className, size = 17 }) => (
  <svg {...svgProps(size, className)} fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round">
    <path d="M5.5 3.5h9l4 4v13h-13z" strokeLinejoin="round" />
    <path d="M14.5 3.5v4h4M8 12h8M8 15.5h8M8 19h5" />
  </svg>
);

const RelatedDocumentsIcon: React.FC<IIconProps> = ({ className, size = 17 }) => (
  <svg {...svgProps(size, className)} fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinejoin="round">
    <path d="M8 3.5h11v13H8z" />
    <path d="M5 6.5v14h11" strokeLinecap="round" />
  </svg>
);

const ChatIcon: React.FC<IIconProps> = ({ className, size = 17 }) => (
  <svg {...svgProps(size, className)} fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinejoin="round">
    <path d="M20 13.5a3 3 0 01-3 3H9l-5 3.5v-14a3 3 0 013-3h10a3 3 0 013 3z" />
  </svg>
);

export const SendIcon: React.FC<IIconProps> = ({ className, size = 16 }) => (
  <svg {...svgProps(size, className)} fill="none" stroke="currentColor" strokeWidth={1.9} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 19V5M5.5 11.5L12 5l6.5 6.5" />
  </svg>
);

const ACTION_ICONS: { [key in AssistantActionId]: React.FC<IIconProps> } = {
  summarizePage: SummarizeIcon,
  findRelatedDocuments: RelatedDocumentsIcon,
  openChat: ChatIcon
};

export const ActionIcon: React.FC<IIconProps & { id: AssistantActionId }> = ({ id, ...rest }) => {
  const Icon = ACTION_ICONS[id];
  return Icon ? <Icon {...rest} /> : null;
};
