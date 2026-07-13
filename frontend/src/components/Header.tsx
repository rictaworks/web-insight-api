'use client';

import '@/config/fontAwesome';
import React, { useState, useRef, useEffect } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faMagnifyingGlass, faUser, faChevronDown, faGlobe } from '@fortawesome/free-solid-svg-icons';
import { useLocale } from './LocaleContext';
import { locales, Locale } from '@/config/i18n';
import { messages } from '@/config/messages';

export default function Header() {
  const { locale, setLocale } = useLocale();
  const [showLanguages, setShowLanguages] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
  const langRef = useRef<HTMLDivElement>(null);
  const userRef = useRef<HTMLDivElement>(null);

  const t = (key: keyof typeof messages['ja']) => {
    return messages[locale]?.[key] || messages['ja'][key] || key;
  };

  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (langRef.current && !langRef.current.contains(event.target as Node)) {
        setShowLanguages(false);
      }
      if (userRef.current && !userRef.current.contains(event.target as Node)) {
        setShowUserMenu(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const languageLabels: Record<Locale, string> = {
    ja: '日本語',
    en: 'English',
    fr: 'Français',
    zh: '中文',
    ru: 'Русский',
    es: 'Español',
    ar: 'العربية',
  };

  return (
    <header className="header">
      <div className="search-box">
        <span className="search-icon">
          <FontAwesomeIcon icon={faMagnifyingGlass} />
        </span>
        <input
          type="text"
          placeholder={t('searchPlaceholder')}
          className="search-input"
        />
      </div>

      <div className="header-right">
        {/* Language Selector */}
        <div className="language-selector" ref={langRef}>
          <button
            onClick={() => setShowLanguages(!showLanguages)}
            className="language-btn"
            aria-label="Select Language"
          >
            <FontAwesomeIcon icon={faGlobe} />
            <span>{languageLabels[locale]}</span>
            <FontAwesomeIcon icon={faChevronDown} style={{ fontSize: '10px' }} />
          </button>
          {showLanguages && (
            <div className="language-dropdown">
              {locales.map((loc) => (
                <button
                  key={loc}
                  onClick={() => {
                    setLocale(loc);
                    setShowLanguages(false);
                  }}
                  className={`language-option ${locale === loc ? 'active' : ''}`}
                >
                  {languageLabels[loc]}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* User Profile Menu */}
        <div className="user-menu" ref={userRef}>
          <button
            type="button"
            className="user-menu-trigger"
            onClick={() => setShowUserMenu(!showUserMenu)}
            aria-haspopup="true"
            aria-expanded={showUserMenu}
            aria-label={t('userMenu')}
          >
            <div className="user-avatar">
              <FontAwesomeIcon icon={faUser} />
            </div>
            <span className="user-name">Demo User</span>
            <FontAwesomeIcon icon={faChevronDown} style={{ fontSize: '10px', color: 'var(--text-muted)' }} />
          </button>

          {showUserMenu && (
            <div className="user-dropdown">
              <button className="user-dropdown-item">{t('userProfile')}</button>
              <button className="user-dropdown-item">{t('settings')}</button>
              <hr style={{ border: 'none', borderBottom: '1px solid var(--border)', margin: '4px 0' }} />
              <button className="user-dropdown-item" style={{ color: '#dc2626' }}>{t('logout')}</button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
