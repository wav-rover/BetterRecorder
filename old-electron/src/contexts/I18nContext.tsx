import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from 'react'
import {
  DEFAULT_LOCALE,
  I18N_NAMESPACES,
  type I18nNamespace,
} from '@/i18n/config'
import enCommon from '@/i18n/locales/en/common.json'
import enDialogs from '@/i18n/locales/en/dialogs.json'
import enEditor from '@/i18n/locales/en/editor.json'
import enLaunch from '@/i18n/locales/en/launch.json'
import enSettings from '@/i18n/locales/en/settings.json'
import enShortcuts from '@/i18n/locales/en/shortcuts.json'
import enTimeline from '@/i18n/locales/en/timeline.json'

type LocaleBundle = Record<I18nNamespace, Record<string, unknown>>

const messages: LocaleBundle = {
  common: enCommon,
  launch: enLaunch,
  editor: enEditor,
  timeline: enTimeline,
  settings: enSettings,
  dialogs: enDialogs,
  shortcuts: enShortcuts,
}

interface I18nContextValue {
  t: (key: string, fallback?: string, vars?: Record<string, string | number>) => string
}

const I18nContext = createContext<I18nContextValue | null>(null)

function getMessageValue(source: unknown, key: string): string | undefined {
  const parts = key.split('.')
  let current: unknown = source

  for (const part of parts) {
    if (!current || typeof current !== 'object' || !(part in current)) {
      return undefined
    }

    current = (current as Record<string, unknown>)[part]
  }

  return typeof current === 'string' ? current : undefined
}

function interpolate(template: string, vars?: Record<string, string | number>) {
  if (!vars) return template
  return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_match, key) => {
    const value = vars[key]
    return value === undefined ? '' : String(value)
  })
}

function parseKey(key: string): { namespace: I18nNamespace; path: string } {
  const [first, ...rest] = key.split('.')
  if (I18N_NAMESPACES.includes(first as I18nNamespace) && rest.length > 0) {
    return { namespace: first as I18nNamespace, path: rest.join('.') }
  }
  return { namespace: 'common', path: key }
}

function translate(key: string, fallback?: string, vars?: Record<string, string | number>) {
  const { namespace, path } = parseKey(key)

  const rawValue =
    getMessageValue(messages[namespace], path)
    ?? fallback
    ?? key

  return interpolate(rawValue, vars)
}

export function I18nProvider({ children }: { children: ReactNode }) {
  useEffect(() => {
    document.documentElement.lang = DEFAULT_LOCALE
  }, [])

  const t = useCallback((key: string, fallback?: string, vars?: Record<string, string | number>) => {
    return translate(key, fallback, vars)
  }, [])

  const value = useMemo<I18nContextValue>(() => ({
    t,
  }), [t])

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n() {
  const context = useContext(I18nContext)
  if (!context) {
    throw new Error('useI18n must be used within <I18nProvider>')
  }
  return context
}

export function useScopedT(namespace: I18nNamespace) {
  const { t } = useI18n()
  return useCallback((key: string, fallback?: string, vars?: Record<string, string | number>) => {
    return t(`${namespace}.${key}`, fallback, vars)
  }, [namespace, t])
}
