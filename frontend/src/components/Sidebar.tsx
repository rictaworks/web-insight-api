'use client';

import '@/config/fontAwesome';
import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import {
  faChartPie,
  faGlobe,
  faFire,
  faFilter,
  faHistory,
  faBolt,
  faBell,
  faBrain
} from '@fortawesome/free-solid-svg-icons';
import { useLocale } from './LocaleContext';
import { messages } from '@/config/messages';

export default function Sidebar() {
  const pathname = usePathname();
  const { locale } = useLocale();

  const t = (key: keyof typeof messages['ja']) => {
    return messages[locale]?.[key] || messages['ja'][key] || key;
  };

  const navItems = [
    { name: t('dashboard'), path: '/dashboard', icon: faChartPie },
    { name: t('sites'), path: '/sites', icon: faGlobe },
    { name: t('heatmaps'), path: '/heatmaps', icon: faFire },
    { name: t('funnels'), path: '/funnels', icon: faFilter },
    { name: t('retention'), path: '/retention', icon: faHistory },
    { name: t('performance'), path: '/performance', icon: faBolt },
    { name: t('alerts'), path: '/alerts', icon: faBell },
    { name: t('aiRecommendation'), path: '/ai-recommendation', icon: faBrain },
  ];

  return (
    <aside className="sidebar">
      <div className="sidebar-brand">
        <FontAwesomeIcon icon={faChartPie} />
        <span>{t('brandName')}</span>
      </div>
      <nav className="sidebar-nav">
        {navItems.map((item) => {
          const isActive = pathname === item.path;
          return (
            <Link
              key={item.path}
              href={item.path}
              className={`nav-item ${isActive ? 'active' : ''}`}
            >
              <span className="nav-item-icon">
                <FontAwesomeIcon icon={item.icon} />
              </span>
              <span>{item.name}</span>
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
