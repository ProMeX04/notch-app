import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
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
        <script
          id="portal-bfcache-refresh"
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                window.addEventListener('pageshow', function(event) {
                  var isBack = event.persisted;
                  if (!isBack && window.performance) {
                    var entries = window.performance.getEntriesByType('navigation');
                    if (entries.length > 0) {
                      isBack = entries[0].type === 'back_forward';
                    } else if (window.performance.navigation) {
                      isBack = window.performance.navigation.type === 2;
                    }
                  }
                  if (isBack) {
                    window.location.reload();
                  }
                });
              })();
            `
          }}
        />
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
