'use client';

import React from 'react';
import { useLocale } from './LocaleContext';
import { messages } from '@/config/messages';

type MessageKey = keyof typeof messages['ja'];

export default function PlaceholderPage({ messageKey }: { messageKey: MessageKey }) {
  const { locale } = useLocale();

  const t = (key: MessageKey) => {
    return messages[locale]?.[key] || messages['ja'][key] || key;
  };

  return (
    <div>
      <h1>{t(messageKey)}</h1>
    </div>
  );
}
