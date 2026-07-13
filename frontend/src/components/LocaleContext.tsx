'use client';

import React, { createContext, useContext, useState, useEffect } from 'react';
import { Locale, defaultLocale } from '@/config/i18n';

type LocaleContextType = {
  locale: Locale;
  setLocale: (locale: Locale) => void;
};

const LocaleContext = createContext<LocaleContextType | undefined>(undefined);

const RTL_LOCALES: Locale[] = ['ar'];

function applyDocumentLocale(locale: Locale) {
  document.documentElement.lang = locale;
  document.documentElement.dir = RTL_LOCALES.includes(locale) ? 'rtl' : 'ltr';
}

export function LocaleProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState<Locale>(defaultLocale);

  useEffect(() => {
    const saved = localStorage.getItem('app-locale') as Locale;
    if (saved && ['ja', 'en', 'fr', 'zh', 'ru', 'es', 'ar'].includes(saved)) {
      setLocale(saved);
      applyDocumentLocale(saved);
    } else {
      const lang = navigator.language.split('-')[0] as Locale;
      if (['ja', 'en', 'fr', 'zh', 'ru', 'es', 'ar'].includes(lang)) {
        setLocale(lang);
        applyDocumentLocale(lang);
      }
    }
  }, []);

  const changeLocale = (newLocale: Locale) => {
    setLocale(newLocale);
    localStorage.setItem('app-locale', newLocale);
    applyDocumentLocale(newLocale);
  };

  return (
    <LocaleContext.Provider value={{ locale, setLocale: changeLocale }}>
      {children}
    </LocaleContext.Provider>
  );
}

export function useLocale() {
  const context = useContext(LocaleContext);
  if (!context) {
    throw new Error('useLocale must be used within a LocaleProvider');
  }
  return context;
}
