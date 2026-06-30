export const locales = ['ja', 'en', 'fr', 'zh', 'ru', 'es', 'ar'] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = 'ja';
