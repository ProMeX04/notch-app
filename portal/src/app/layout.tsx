import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import Script from "next/script";
import { PortalAuthProvider } from "@/components/portal/PortalAuthProvider";
import { PortalPendingLogoutFlusher } from "@/components/portal/PortalPendingLogoutFlusher";
import { QueryProvider } from "@/components/portal/QueryProvider";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Notch | Focus, drag & drop và điều khiển media ngay trên notch",
  description:
    "Notch là app notch cho macOS giúp bạn focus với Pomodoro, kéo thả file vào shelf, điều khiển media và dùng Gemini Live trong một giao diện gọn nhẹ.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="vi" className={`${geistSans.variable} ${geistMono.variable}`} data-scroll-behavior="smooth">
      <body className="portal-body">
        <Script id="portal-bfcache-refresh" strategy="afterInteractive">
          {`
            (function() {
              window.addEventListener('pageshow', function(event) {
                if (event.persisted || (window.performance && window.performance.navigation && window.performance.navigation.type === 2)) {
                  window.location.reload();
                }
              });
            })();
          `}
        </Script>
        <QueryProvider>
          <PortalAuthProvider>
            <PortalPendingLogoutFlusher />
            {children}
          </PortalAuthProvider>
        </QueryProvider>
      </body>
    </html>
  );
}
