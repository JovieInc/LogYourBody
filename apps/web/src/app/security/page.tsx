import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { logYourBody } from '@jovieinc/product-registry';

export default function SecurityPage() {
  return (
    <div className="bg-linear-bg font-inter min-h-svh">
      <Header />
      <main>
        <section className="py-16 md:py-24">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-2xl">
              <h1 className="text-linear-text mb-6 text-4xl font-bold tracking-tight">
                Report a security issue
              </h1>
              <p className="text-linear-text-secondary mb-8 text-lg">
                If you found a vulnerability in {logYourBody.identity.name}, report it privately
                through GitHub. Do not post vulnerability details in a public issue.
              </p>
              <Card className="border-linear-border bg-linear-card">
                <CardHeader>
                  <CardTitle className="text-linear-text">Private reporting</CardTitle>
                </CardHeader>
                <CardContent className="space-y-6">
                  <p className="text-linear-text-secondary">
                    You will need to sign in to GitHub to write and submit your report. Opening the
                    link below does not submit a report.
                  </p>
                  <Button asChild>
                    <a href={`${logYourBody.links.github}/security/advisories/new`}>
                      Report privately on GitHub
                    </a>
                  </Button>
                  <div className="text-linear-text-secondary space-y-2">
                    <h2 className="text-linear-text font-semibold">What to include</h2>
                    <ul className="list-disc space-y-2 pl-5">
                      <li>The affected feature, app version, or page.</li>
                      <li>Steps to reproduce the issue and its potential impact.</li>
                      <li>A safe example with personal data and secrets removed.</li>
                    </ul>
                  </div>
                  <p className="text-linear-text-secondary text-sm">
                    Avoid accessing other people&apos;s data or performing destructive tests.
                  </p>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
