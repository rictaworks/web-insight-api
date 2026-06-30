import type { Metadata } from "next";
import "./globals.css";
import { defaultLocale } from "@/config/i18n";

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
      <body>{children}</body>
    </html>
  );
}
