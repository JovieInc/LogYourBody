'use client';

import React from 'react';
import Image from 'next/image';
import { Button } from '@/components/ui/button';
import { Download, Copy, Check } from 'lucide-react';
import { useState } from 'react';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { logYourBody } from '@jovieinc/product-registry';

export default function BrandPage() {
  const [copiedItem, setCopiedItem] = useState<string | null>(null);

  const copyToClipboard = (text: string, item: string) => {
    navigator.clipboard.writeText(text);
    setCopiedItem(item);
    setTimeout(() => setCopiedItem(null), 2000);
  };

  const colors = {
    primary: [
      {
        name: 'Accent',
        hex: logYourBody.brand.colors.accent,
        rgb: 'rgb(94, 106, 210)',
        usage: 'Metric meaning and state',
      },
      { name: 'Purple Light', hex: '#8B92E8', rgb: 'rgb(139, 146, 232)', usage: 'Hover states' },
      { name: 'Purple Dark', hex: '#4752C4', rgb: 'rgb(71, 82, 196)', usage: 'Active states' },
    ],
    neutral: [
      {
        name: 'Background',
        hex: logYourBody.brand.colors.background,
        rgb: 'rgb(8, 9, 10)',
        usage: 'Main background',
      },
      { name: 'Card', hex: '#18181B', rgb: 'rgb(24, 24, 27)', usage: 'Card backgrounds' },
      { name: 'Border', hex: '#27272A', rgb: 'rgb(39, 39, 42)', usage: 'Borders, dividers' },
    ],
    text: [
      { name: 'Primary', hex: '#FAFAFA', rgb: 'rgb(250, 250, 250)', usage: 'Main text' },
      { name: 'Secondary', hex: '#A1A1AA', rgb: 'rgb(161, 161, 170)', usage: 'Secondary text' },
      { name: 'Tertiary', hex: '#71717A', rgb: 'rgb(113, 113, 122)', usage: 'Disabled, hints' },
    ],
    semantic: [
      { name: 'Success', hex: '#22C55E', rgb: 'rgb(34, 197, 94)', usage: 'Success states' },
      { name: 'Warning', hex: '#F59E0B', rgb: 'rgb(245, 158, 11)', usage: 'Warning states' },
      { name: 'Error', hex: '#EF4444', rgb: 'rgb(239, 68, 68)', usage: 'Error states' },
    ],
  };

  const typography = {
    fonts: [
      {
        name: 'Inter',
        weights: ['400', '500', '600', '700'],
        usage: 'Primary font for all UI elements',
        sample: 'The quick brown fox jumps over the lazy dog',
      },
      {
        name: 'SF Mono',
        weights: ['400', '500'],
        usage: 'Monospace font for code and numbers',
        sample: '0123456789 {code: "example"}',
      },
    ],
    scale: [
      { name: 'Display', size: '48px', lineHeight: '56px', weight: '700' },
      { name: 'Heading 1', size: '36px', lineHeight: '44px', weight: '700' },
      { name: 'Heading 2', size: '30px', lineHeight: '38px', weight: '600' },
      { name: 'Heading 3', size: '24px', lineHeight: '32px', weight: '600' },
      { name: 'Body Large', size: '18px', lineHeight: '28px', weight: '400' },
      { name: 'Body', size: '16px', lineHeight: '24px', weight: '400' },
      { name: 'Body Small', size: '14px', lineHeight: '20px', weight: '400' },
      { name: 'Caption', size: '12px', lineHeight: '16px', weight: '400' },
    ],
  };

  const logos = [
    {
      name: 'App icon',
      description: 'Canonical product mark for app and compact product surfaces.',
      src: logYourBody.brand.logos.appIcon,
    },
    logYourBody.brand.logos.wordmark
      ? {
          name: 'Wordmark',
          description: 'Canonical horizontal wordmark.',
          src: logYourBody.brand.logos.wordmark,
        }
      : null,
  ].filter((logo): logo is { name: string; description: string; src: string } => logo !== null);

  return (
    <div className="bg-background min-h-screen">
      <Header />

      <main className="container mx-auto px-4 py-12 sm:px-6">
        {/* Hero Section */}
        <section className="mx-auto mb-24 max-w-4xl">
          <div className="mb-12 text-center">
            <h1 className="text-linear-text mb-6 text-4xl font-bold sm:text-5xl md:text-6xl">
              {logYourBody.identity.name} Brand
            </h1>
            <p className="text-linear-text-secondary mx-auto max-w-2xl text-xl">
              {logYourBody.brand.promise}
            </p>
          </div>
        </section>

        {/* Logo Section */}
        <section className="mx-auto mb-24 max-w-6xl">
          <div className="mb-12">
            <h2 className="text-linear-text mb-4 text-3xl font-bold">Logo</h2>
            <p className="text-linear-text-secondary max-w-3xl">
              Our logo embodies strength and progress. Use it consistently to maintain brand
              recognition.
            </p>
          </div>

          <div className="grid grid-cols-1 gap-8 md:grid-cols-2">
            {logos.map((logo) => (
              <div key={logo.name} className="group">
                <div className="bg-linear-card border-linear-border group-hover:border-linear-purple/30 mb-4 flex h-48 items-center justify-center rounded-xl border p-8 transition-all">
                  <Image
                    src={logo.src}
                    alt={`${logo.name} for ${logYourBody.identity.name}`}
                    width={96}
                    height={96}
                  />
                </div>
                <h3 className="text-linear-text mb-1 text-lg font-semibold">{logo.name}</h3>
                <p className="text-linear-text-secondary text-sm">{logo.description}</p>
              </div>
            ))}
          </div>

          <div className="bg-linear-card/50 border-linear-border mt-12 rounded-xl border p-6">
            <h3 className="text-linear-text mb-4 text-lg font-semibold">Usage Guidelines</h3>
            <ul className="text-linear-text-secondary space-y-2 text-sm">
              <li>• Maintain clear space equal to the height of the "L" around the logo</li>
              <li>• Never stretch, rotate, or distort the logo</li>
              <li>• Ensure sufficient contrast between logo and background</li>
              <li>• Minimum size: 24px height for icon, 120px width for full logo</li>
            </ul>
          </div>
        </section>

        {/* Colors Section */}
        <section className="mx-auto mb-24 max-w-6xl">
          <div className="mb-12">
            <h2 className="text-linear-text mb-4 text-3xl font-bold">Colors</h2>
            <p className="text-linear-text-secondary max-w-3xl">
              Our color palette reflects the precision and sophistication of body transformation
              tracking.
            </p>
          </div>

          {Object.entries(colors).map(([category, colorSet]) => (
            <div key={category} className="mb-12">
              <h3 className="text-linear-text mb-6 text-xl font-semibold capitalize">{category}</h3>
              <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
                {colorSet.map((color) => (
                  <div key={color.name} className="group">
                    <div
                      className="relative mb-4 h-32 cursor-pointer overflow-hidden rounded-xl transition-transform group-hover:scale-105"
                      style={{ backgroundColor: color.hex }}
                      onClick={() => copyToClipboard(color.hex, color.name)}
                    >
                      {copiedItem === color.name && (
                        <div className="absolute inset-0 flex items-center justify-center bg-black/20">
                          <div className="flex items-center gap-2 rounded-lg bg-white/20 px-3 py-1.5 backdrop-blur-sm">
                            <Check className="h-4 w-4 text-white" />
                            <span className="text-sm font-medium text-white">Copied</span>
                          </div>
                        </div>
                      )}
                    </div>
                    <div className="space-y-1">
                      <h4 className="text-linear-text font-semibold">{color.name}</h4>
                      <div className="text-linear-text-secondary flex items-center gap-2 text-sm">
                        <code className="font-mono">{color.hex}</code>
                        <button
                          onClick={() => copyToClipboard(color.hex, color.name)}
                          className="opacity-0 transition-opacity group-hover:opacity-100"
                        >
                          <Copy className="h-3 w-3" />
                        </button>
                      </div>
                      <p className="text-linear-text-tertiary text-sm">{color.usage}</p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </section>

        {/* Typography Section */}
        <section className="mx-auto mb-24 max-w-6xl">
          <div className="mb-12">
            <h2 className="text-linear-text mb-4 text-3xl font-bold">Typography</h2>
            <p className="text-linear-text-secondary max-w-3xl">
              Clean, modern typography that enhances readability and conveys professionalism.
            </p>
          </div>

          {/* Font Families */}
          <div className="mb-16">
            <h3 className="text-linear-text mb-6 text-xl font-semibold">Font Families</h3>
            <div className="space-y-8">
              {typography.fonts.map((font) => (
                <div
                  key={font.name}
                  className="bg-linear-card border-linear-border rounded-xl border p-6"
                >
                  <div className="mb-4 flex items-start justify-between">
                    <div>
                      <h4 className="text-linear-text mb-1 text-lg font-semibold">{font.name}</h4>
                      <p className="text-linear-text-secondary text-sm">{font.usage}</p>
                    </div>
                    <div className="flex gap-2">
                      {font.weights.map((weight) => (
                        <span
                          key={weight}
                          className="bg-linear-bg text-linear-text-secondary rounded-md px-2 py-1 text-xs"
                        >
                          {weight}
                        </span>
                      ))}
                    </div>
                  </div>
                  <p
                    className="text-linear-text text-2xl"
                    style={{ fontFamily: font.name === 'SF Mono' ? 'monospace' : 'Inter' }}
                  >
                    {font.sample}
                  </p>
                </div>
              ))}
            </div>
          </div>

          {/* Type Scale */}
          <div>
            <h3 className="text-linear-text mb-6 text-xl font-semibold">Type Scale</h3>
            <div className="space-y-6">
              {typography.scale.map((style) => (
                <div
                  key={style.name}
                  className="hover:bg-linear-card/50 flex items-baseline gap-8 rounded-lg p-4 transition-colors"
                >
                  <div className="w-32 flex-shrink-0">
                    <span className="text-linear-text-secondary text-sm">{style.name}</span>
                  </div>
                  <div className="flex-1">
                    <p
                      className="text-linear-text"
                      style={{
                        fontSize: style.size,
                        lineHeight: style.lineHeight,
                        fontWeight: style.weight,
                      }}
                    >
                      The quick brown fox jumps over the lazy dog
                    </p>
                  </div>
                  <div className="text-linear-text-tertiary font-mono text-sm">
                    {style.size} / {style.lineHeight}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Voice & Tone Section */}
        <section className="mx-auto mb-24 max-w-4xl">
          <div className="mb-12">
            <h2 className="text-linear-text mb-4 text-3xl font-bold">Voice & Tone</h2>
            <p className="text-linear-text-secondary max-w-3xl">
              We speak with confidence and clarity, focusing on results and transformation.
            </p>
          </div>

          <div className="grid grid-cols-1 gap-8 md:grid-cols-2">
            <div className="bg-linear-card border-linear-border rounded-xl border p-6">
              <h3 className="text-linear-text mb-4 text-lg font-semibold">We are</h3>
              <ul className="text-linear-text-secondary space-y-2">
                <li>✓ Direct and honest</li>
                <li>✓ Results-focused</li>
                <li>✓ Encouraging but realistic</li>
                <li>✓ Professional yet approachable</li>
                <li>✓ Data-driven</li>
              </ul>
            </div>
            <div className="bg-linear-card border-linear-border rounded-xl border p-6">
              <h3 className="text-linear-text mb-4 text-lg font-semibold">We are not</h3>
              <ul className="text-linear-text-secondary space-y-2">
                <li>✗ Preachy or judgmental</li>
                <li>✗ Overly technical</li>
                <li>✗ Making false promises</li>
                <li>✗ Casual or unprofessional</li>
                <li>✗ Vague or ambiguous</li>
              </ul>
            </div>
          </div>

          <div className="bg-linear-purple/10 border-linear-purple/20 mt-8 rounded-xl border p-6">
            <h3 className="text-linear-text mb-3 text-lg font-semibold">Example messaging</h3>
            <p className="text-linear-text-secondary italic">
              "Track what matters. See real progress. Professional body composition tracking that
              shows you exactly how you're transforming."
            </p>
          </div>
        </section>

        {/* Download Section */}
        <section className="mx-auto max-w-4xl py-12 text-center">
          <div className="bg-linear-card border-linear-border rounded-xl border p-8">
            <h2 className="text-linear-text mb-4 text-2xl font-bold">Need our brand assets?</h2>
            <p className="text-linear-text-secondary mb-6">
              Download logos, colors, and guidelines in various formats.
            </p>
            <Button size="lg" className="gap-2" disabled>
              <Download className="h-5 w-5" />
              Download Brand Package
            </Button>
            <p className="text-linear-text-tertiary mt-4 text-sm">Coming soon</p>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
