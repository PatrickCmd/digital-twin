import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { profile, siteUrl } from "@/content/profile";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const title = `${profile.full_name} | AI Digital Twin`;
const description = `${profile.headline} Ask ${profile.name}'s AI digital twin about his experience, stack and availability.`;

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title,
  description,
  alternates: { canonical: "/" },
  openGraph: {
    type: "profile",
    url: siteUrl,
    title,
    description,
    siteName: `${profile.full_name} - AI Digital Twin`,
    images: [{ url: "/og.png", width: 1200, height: 630, alt: `${profile.full_name}, ${profile.title}` }],
    firstName: profile.full_name.split(" ")[0],
    lastName: profile.full_name.split(" ").slice(1).join(" "),
  },
  twitter: {
    card: "summary_large_image",
    title,
    description,
    images: ["/og.png"],
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f8fafc" },
    { media: "(prefers-color-scheme: dark)", color: "#020617" },
  ],
};

const personJsonLd = {
  "@context": "https://schema.org",
  "@type": "Person",
  name: profile.full_name,
  jobTitle: profile.title,
  description: profile.headline,
  email: `mailto:${profile.email}`,
  url: profile.links.website,
  image: `${siteUrl}/avatar.png`,
  address: { "@type": "PostalAddress", addressLocality: profile.location.split(",")[0].trim(), addressCountry: "UG" },
  sameAs: [profile.links.github, profile.links.linkedin, profile.links.website].filter(Boolean),
  knowsAbout: profile.specialties,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-slate-50 dark:bg-slate-950">
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(personJsonLd).replace(/</g, "\\u003c") }}
        />
        {children}
      </body>
    </html>
  );
}
