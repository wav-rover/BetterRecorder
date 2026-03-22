export const DEFAULT_LOCALE = 'en' as const

/** English-only build; kept for typing and future single-locale expansion. */
export const SUPPORTED_LOCALES = ['en'] as const

export const I18N_NAMESPACES = [
  'common',
  'launch',
  'editor',
  'timeline',
  'settings',
  'dialogs',
  'shortcuts',
] as const

export type AppLocale = (typeof SUPPORTED_LOCALES)[number]
export type I18nNamespace = (typeof I18N_NAMESPACES)[number]
