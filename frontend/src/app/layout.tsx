import type { Metadata } from "next";
import "./globals.css";
import { defaultLocale } from "@/config/i18n";
import { LocaleProvider } from "@/components/LocaleContext";
import Sidebar from "@/components/Sidebar";
import Header from "@/components/Header";
import { Noto_Sans_JP, Barlow_Condensed } from "next/font/google";

// Prevent Font Awesome from dynamically adding its CSS since we're bundling it
import "@/config/fontAwesome";

const notoSansJP = Noto_Sans_JP({
  subsets: ["latin"],
  weight: ["400", "500", "700"], // 本文(400)・.nav-item/.user-name(500)・.language-option.active(700)
  variable: "--font-body",
});

const barlowCondensed = Barlow_Condensed({
  subsets: ["latin"],
  weight: ["700"], // .sidebar-brand のみで使用
  variable: "--font-display",
});

export const metadata: Metadata = {
  title: "web-insight-api",
  description: "ウェブサイト計測・解析・改善提案 OSS API",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang={defaultLocale}>
      <body className={`${notoSansJP.variable} ${barlowCondensed.variable}`}>
        <LocaleProvider>
          <div className="layout-container">
            <Sidebar />
            <div className="main-wrapper">
              <Header />
              <main className="content">{children}</main>
            </div>
          </div>
        </LocaleProvider>
      </body>
    </html>
  );
}
