import { Header } from './Header';
import { Footer } from './Footer';

/** The shared secondary-route shell. The launch hero keeps its own composition. */
export function MarketingPage({ children }: { children: React.ReactNode }) {
  return (
    <div className="lyb-marketing min-h-svh">
      <a
        href="#main-content"
        className="bg-btn-primary text-btn-primary-foreground sr-only z-50 rounded-full px-4 py-2 focus:not-sr-only focus:fixed focus:top-4 focus:left-4"
      >
        Skip to content
      </a>
      <Header />
      <main
        id="main-content"
        tabIndex={-1}
        className="max-w-public-content mx-auto px-5 py-16 sm:px-8 md:py-24"
      >
        {children}
      </main>
      <Footer />
    </div>
  );
}
