import { Metadata } from 'next';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent } from '@/components/ui/card';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import {
  BarChart3,
  Camera,
  TrendingUp,
  Users,
  Target,
  Shield,
  Award,
  Zap,
  Rocket,
  Activity,
} from 'lucide-react';
import { getAllTeamMembers, formatBodyStats } from '@/lib/team';

export const metadata: Metadata = {
  title: 'About - LogYourBody',
  description:
    'Learn about LogYourBody and our mission to help people track their body composition effectively. Built for outcomes, not engagement.',
  openGraph: {
    title: 'About LogYourBody - Body Composition Tracking',
    description:
      'Professional-grade body composition tracking tools that are beautiful, accurate, and inspire real progress.',
    type: 'website',
  },
};

export default function AboutPage() {
  const values = [
    {
      icon: Target,
      title: 'Obsess Over Outcomes',
      description: 'We measure success by real body-composition wins, not vanity metrics.',
    },
    {
      icon: Award,
      title: 'Be Undeniably Better',
      description:
        'We compete by being so superior that switching feels like downgrading. Quality is our only sustainable moat.',
    },
    {
      icon: BarChart3,
      title: 'Science Over Stories',
      description:
        'Evidence-based decisions, not feelings. Scientific accuracy even when the truth is uncomfortable.',
    },
    {
      icon: Zap,
      title: 'Effortless Science',
      description: 'Complex metrics made simple.',
    },
    {
      icon: Shield,
      title: 'Privacy First',
      description:
        'Your body data is deeply personal. We make privacy our differentiator through transparency and control.',
    },
    {
      icon: Rocket,
      title: 'Move Fast, Break Often',
      description:
        'Move quickly with a bias for action. Regularly step back to see how your efforts fit into the bigger picture. Embrace a cycle of sprinting, walking, and repeating.',
    },
  ];

  const stats = [
    { number: 'iOS', label: 'Native Product' },
    { number: 'HealthKit', label: 'Connected Data' },
    { number: 'Private', label: 'Body Timeline' },
    { number: '30 sec', label: 'Average Log Time' },
  ];

  const teamMembers = [
    {
      name: 'Tim White',
      role: 'Founder & Developer',
      bio: 'Passionate about creating tools that help people understand their bodies better. 10+ years in software development with a focus on health and fitness technology.',
      avatar: 'TW',
    },
  ];

  return (
    <div className="bg-linear-bg font-inter min-h-screen">
      <Header />

      <main>
        {/* Hero Section */}
        <section className="py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-4xl text-center">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-6 inline-block">
                Our Story
              </Badge>
              <h1 className="text-linear-text mb-6 text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl">
                Building the future of
                <br />
                body composition tracking
              </h1>
              <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg">
                We&apos;re building the future of body composition tracking. Not another vanity
                metrics app, but professional-grade tools that are beautiful, accurate, and inspire
                real progress.
              </p>
            </div>
          </div>
        </section>

        {/* Stats Section */}
        <section className="border-linear-border border-y py-12">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="grid grid-cols-2 gap-8 text-center md:grid-cols-4">
              {stats.map((stat, index) => (
                <div key={index}>
                  <div className="text-linear-text mb-2 text-3xl font-bold">{stat.number}</div>
                  <div className="text-linear-text-secondary text-sm">{stat.label}</div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Mission Section */}
        <section className="py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="grid gap-16 lg:grid-cols-2 lg:items-center">
              <div>
                <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-4 inline-block">
                  Our Mission
                </Badge>
                <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                  Built for outcomes, not engagement
                </h2>
                <div className="text-linear-text-secondary space-y-6 text-lg">
                  <p>
                    Most fitness apps optimize for daily active users, not actual results.
                    They&apos;re built to keep you engaged, not help you achieve real body
                    composition changes.
                  </p>
                  <p>
                    We obsess over user outcomes. Every feature must help you lose fat, gain muscle,
                    or understand your body better. We track body fat percentage, lean mass, and
                    FFMI—the metrics that actually matter.
                  </p>
                  <p>
                    Body-composition signals in one clear timeline. We compete by making progress
                    easier to understand, not by making inflated accuracy claims.
                  </p>
                </div>
              </div>

              <div className="grid gap-6 sm:grid-cols-2">
                <div className="border-linear-border bg-linear-card rounded-lg border p-6">
                  <BarChart3 className="text-linear-purple mb-4 h-8 w-8" />
                  <h3 className="text-linear-text mb-2 text-lg font-semibold">
                    Professional Grade
                  </h3>
                  <p className="text-linear-text-secondary text-sm">
                    Weight, body fat, lean mass, and related metrics presented with their method and
                    context.
                  </p>
                </div>
                <div className="border-linear-border bg-linear-card rounded-lg border p-6">
                  <Camera className="text-linear-purple mb-4 h-8 w-8" />
                  <h3 className="text-linear-text mb-2 text-lg font-semibold">Visual Progress</h3>
                  <p className="text-linear-text-secondary text-sm">
                    See changes your scale can&apos;t measure. Automated photo reminders with
                    consistent angles.
                  </p>
                </div>
                <div className="border-linear-border bg-linear-card rounded-lg border p-6">
                  <TrendingUp className="text-linear-purple mb-4 h-8 w-8" />
                  <h3 className="text-linear-text mb-2 text-lg font-semibold">FFMI Tracking</h3>
                  <p className="text-linear-text-secondary text-sm">
                    Know your genetic potential. Track lean muscle gains without the guesswork.
                  </p>
                </div>
                <div className="border-linear-border bg-linear-card rounded-lg border p-6">
                  <Users className="text-linear-purple mb-4 h-8 w-8" />
                  <h3 className="text-linear-text mb-2 text-lg font-semibold">Built for Results</h3>
                  <p className="text-linear-text-secondary text-sm">
                    From personal use to professional coaching. Tools that actually move the needle.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Values Section */}
        <section className="bg-linear-card/30 py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-4 inline-block">
                Our Values
              </Badge>
              <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                What drives us
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                The principles that guide every decision we make and every feature we build.
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {values.map((value, index) => {
                const IconComponent = value.icon;
                return (
                  <div
                    key={index}
                    className="border-linear-border bg-linear-bg hover:bg-linear-card/50 rounded-lg border p-6 text-center transition-colors"
                  >
                    <div className="bg-linear-purple/10 mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-lg">
                      <IconComponent className="text-linear-purple h-6 w-6" />
                    </div>
                    <h3 className="text-linear-text mb-3 text-base font-semibold leading-tight">
                      {value.title}
                    </h3>
                    <p className="text-linear-text-secondary text-sm leading-relaxed">
                      {value.description}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>

        {/* Team Section */}
        <section className="py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-4 inline-block">
                Our Team
              </Badge>
              <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                Meet the founder
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                Founded by a passionate developer dedicated to revolutionizing fitness tracking.
              </p>
            </div>

            <div className="flex justify-center">
              <div className="max-w-md">
                {teamMembers.map((member, index) => (
                  <div
                    key={index}
                    className="border-linear-border bg-linear-card rounded-lg border p-8 text-center"
                  >
                    <div className="bg-linear-purple/10 text-linear-purple mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full text-xl font-bold">
                      {member.avatar}
                    </div>
                    <h3 className="text-linear-text mb-2 text-xl font-semibold">{member.name}</h3>
                    <p className="text-linear-purple mb-4 text-sm font-medium">{member.role}</p>
                    <p className="text-linear-text-secondary text-sm leading-relaxed">
                      {member.bio}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* Open Source Section */}
        <section className="bg-linear-card/30 py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-4xl text-center">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-4 inline-block">
                Open Source
              </Badge>
              <h2 className="text-linear-text mb-6 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                Built in the open
              </h2>
              <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg">
                LogYourBody is open source and built with transparency. We believe the best software
                is created when developers can learn from, contribute to, and improve upon each
                other&apos;s work.
              </p>
              <div className="flex flex-col items-center justify-center gap-4 sm:flex-row">
                <Link
                  href="https://github.com/JovieInc/LogYourBody"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <Button className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary inline-flex items-center gap-2 rounded-lg px-6 py-3 font-medium transition-colors">
                    <svg className="h-5 w-5" fill="currentColor" viewBox="0 0 24 24">
                      <path
                        fillRule="evenodd"
                        d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
                        clipRule="evenodd"
                      />
                    </svg>
                    View on GitHub
                  </Button>
                </Link>
                <p className="text-linear-text-tertiary text-sm">MIT Licensed • Free forever</p>
              </div>
            </div>
          </div>
        </section>

        {/* Team Section */}
        <section className="to-linear-bg/50 bg-gradient-to-b from-transparent py-20 md:py-32">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
                Meet the Team
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                We&apos;re not just building a body composition tracker—we&apos;re using it every
                day. Transparency starts with us.
              </p>
            </div>

            <div className="mx-auto grid max-w-6xl gap-8 md:grid-cols-2 lg:grid-cols-3">
              {getAllTeamMembers().map((member) => {
                const stats = formatBodyStats(member);
                return (
                  <Card
                    key={member.id}
                    className="bg-linear-card border-linear-border hover:border-linear-purple/50 transition-all duration-300"
                  >
                    <CardContent className="p-6">
                      <div className="space-y-4">
                        {/* Header */}
                        <div>
                          <h3 className="text-linear-text mb-1 text-xl font-semibold">
                            {member.name}
                          </h3>
                          <p className="text-linear-text-secondary text-sm">{member.role}</p>
                        </div>

                        {/* Bio */}
                        <p className="text-linear-text-secondary text-sm leading-relaxed">
                          {member.bio}
                        </p>

                        {/* Body Stats */}
                        <div className="border-linear-border grid grid-cols-2 gap-4 border-y py-4">
                          <div className="text-center">
                            <div className="mb-1 flex items-center justify-center gap-1">
                              <Activity className="text-linear-purple h-4 w-4" />
                              <span className="text-linear-text text-lg font-semibold">
                                {stats.bodyFat}
                              </span>
                            </div>
                            <p className="text-linear-text-tertiary text-xs">Body Fat</p>
                          </div>
                          <div className="text-center">
                            <div className="text-linear-text mb-1 text-lg font-semibold">
                              {stats.height}
                            </div>
                            <p className="text-linear-text-tertiary text-xs">Height</p>
                          </div>
                        </div>

                        {/* Achievements */}
                        <div className="space-y-2">
                          <p className="text-linear-text-secondary text-xs font-medium uppercase tracking-wider">
                            Achievements
                          </p>
                          <div className="flex flex-wrap gap-2">
                            {member.achievements.slice(0, 2).map((achievement, idx) => (
                              <Badge
                                key={idx}
                                variant="secondary"
                                className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 text-xs"
                              >
                                {achievement}
                              </Badge>
                            ))}
                          </div>
                        </div>

                        {/* Quote */}
                        <blockquote className="text-linear-text-secondary border-linear-purple border-l-2 pl-4 text-sm italic">
                          &ldquo;{member.quote}&rdquo;
                        </blockquote>

                        {/* Tracking Since */}
                        <div className="flex items-center justify-between pt-2">
                          <p className="text-linear-text-tertiary text-xs">
                            Tracking since {member.bodyStats.trackingSince}
                          </p>
                          {member.social.twitter && (
                            <Link
                              href={member.social.twitter}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="text-linear-text-tertiary hover:text-linear-purple transition-colors"
                            >
                              <svg className="h-4 w-4" fill="currentColor" viewBox="0 0 24 24">
                                <path d="M8.29 20.251c7.547 0 11.675-6.253 11.675-11.675 0-.178 0-.355-.012-.53A8.348 8.348 0 0022 5.92a8.19 8.19 0 01-2.357.646 4.118 4.118 0 001.804-2.27 8.224 8.224 0 01-2.605.996 4.107 4.107 0 00-6.993 3.743 11.65 11.65 0 01-8.457-4.287 4.106 4.106 0 001.27 5.477A4.072 4.072 0 012.8 9.713v.052a4.105 4.105 0 003.292 4.022 4.095 4.095 0 01-1.853.07 4.108 4.108 0 003.834 2.85A8.233 8.233 0 012 18.407a11.616 11.616 0 006.29 1.84" />
                              </svg>
                            </Link>
                          )}
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                );
              })}
            </div>

            <div className="mt-12 text-center">
              <p className="text-linear-text-secondary mb-2 text-sm">
                Want to join our team? We&apos;re looking for people who walk the walk.
              </p>
              <Link href="/careers">
                <Button variant="ghost" className="text-linear-purple hover:text-linear-purple/80">
                  View Open Positions →
                </Button>
              </Link>
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className="py-20 md:py-32">
          <div className="container mx-auto px-4 text-center sm:px-6">
            <h2 className="text-linear-text mb-4 text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl">
              Ready to track real progress?
            </h2>
            <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg">
              Join thousands of people who have already discovered the difference accurate body
              composition tracking makes.
            </p>
            <div className="flex flex-col items-center justify-center gap-4 sm:flex-row">
              <Link href="/download/ios">
                <Button className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-lg px-8 py-4 text-base font-medium transition-colors">
                  Start Free Trial
                </Button>
              </Link>
              <Link href="/">
                <Button
                  variant="ghost"
                  className="border-linear-border text-linear-text-secondary hover:bg-linear-border/50 hover:text-linear-text rounded-lg border px-8 py-4 text-base transition-all"
                >
                  Learn More
                </Button>
              </Link>
            </div>
            <p className="text-linear-text-tertiary mt-4 text-sm">
              No credit card • 3-day trial • Cancel anytime
            </p>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
