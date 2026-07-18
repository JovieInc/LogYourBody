'use client';

import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Header } from '@/components/Header';
import { Footer } from '@/components/Footer';
import { logYourBody } from '@jovieinc/product-registry';
import {
  Users,
  Heart,
  Target,
  Lightbulb,
  Clock,
  Briefcase,
  Mail,
  Coffee,
  Home,
  Globe,
} from 'lucide-react';

export default function CareersPage() {
  const coreValues = [
    {
      icon: Heart,
      title: 'Health First',
      description:
        "We're passionate about helping people understand their bodies and achieve their fitness goals through data-driven insights.",
    },
    {
      icon: Target,
      title: 'Precision & Accuracy',
      description:
        'Every metric matters. We build tools that provide accurate, reliable data people can trust to make important health decisions.',
    },
    {
      icon: Users,
      title: 'User-Centric Design',
      description:
        "Our users' success is our success. We design every feature with real people and real use cases in mind.",
    },
    {
      icon: Lightbulb,
      title: 'Innovation & Growth',
      description:
        "We're always learning, experimenting, and pushing the boundaries of what's possible in fitness technology.",
    },
  ];

  const benefits = [
    {
      icon: Home,
      title: 'Remote-First Culture',
      description:
        'Work from anywhere in the world. We believe great work happens when people have the flexibility they need.',
    },
    {
      icon: Heart,
      title: 'Health & Wellness',
      description:
        'Comprehensive health insurance, mental health support, and a $500 annual fitness stipend.',
    },
    {
      icon: Coffee,
      title: 'Learning & Growth',
      description:
        '$2,000 annual learning budget for courses, conferences, and books. We invest in your professional development.',
    },
    {
      icon: Clock,
      title: 'Flexible Schedule',
      description:
        'Flexible working hours and unlimited PTO. We trust you to manage your time and deliver great work.',
    },
    {
      icon: Globe,
      title: 'Equity & Ownership',
      description: 'Every team member gets equity. When LogYourBody succeeds, everyone succeeds.',
    },
    {
      icon: Users,
      title: 'Amazing Team',
      description:
        "Work with passionate, talented people who care about making a real impact on people's health.",
    },
  ];

  const handleApply = (position: string) => {
    const subject = encodeURIComponent(`Application for ${position} - LogYourBody`);
    const body = encodeURIComponent(`Hi LogYourBody team,

I'm interested in applying for the ${position} position. 

Please find my resume attached, and I'd love to discuss how I can contribute to your mission of helping people track what really matters.

Best regards,
[Your Name]`);

    window.open(`mailto:${logYourBody.contacts.careers}?subject=${subject}&body=${body}`, '_blank');
  };

  return (
    <div className="bg-linear-bg font-inter min-h-screen">
      <Header />

      <main>
        {/* Hero Section */}
        <section className="py-16 md:py-24">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-4xl text-center">
              <Badge className="bg-linear-purple/10 text-linear-purple border-linear-purple/20 mb-6 inline-block">
                Join Our Mission
              </Badge>
              <h1 className="text-linear-text mb-6 text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl">
                Help people track what
                <br />
                <span className="from-linear-purple via-linear-text to-linear-purple bg-gradient-to-r bg-clip-text text-transparent">
                  really matters
                </span>
              </h1>
              <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg">
                We&apos;re building the future of body composition tracking. Join our remote-first
                team and help millions of people understand their bodies better.
              </p>

              <div className="flex flex-col justify-center gap-4 sm:flex-row">
                <Button
                  className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-xl px-8 py-4 text-base font-medium shadow-lg transition-all duration-200 hover:scale-105"
                  onClick={() =>
                    document
                      .getElementById('open-positions')
                      ?.scrollIntoView({ behavior: 'smooth' })
                  }
                >
                  View Open Positions
                </Button>
                <Button
                  variant="ghost"
                  className="border-linear-border/50 text-linear-text-secondary hover:bg-linear-border/30 hover:text-linear-text rounded-xl border px-8 py-4 text-base backdrop-blur-sm transition-all"
                  onClick={() => handleApply('General Application')}
                >
                  Apply Generally
                </Button>
              </div>
            </div>
          </div>
        </section>

        {/* Our Values */}
        <section className="bg-linear-card/30 py-20">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <h2 className="text-linear-text mb-4 text-3xl font-bold sm:text-4xl">
                Our Core Values
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                These values guide everything we do, from product decisions to how we work together.
              </p>
            </div>

            <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-4">
              {coreValues.map((value, index) => {
                const IconComponent = value.icon;
                return (
                  <div
                    key={index}
                    className="border-linear-border bg-linear-bg rounded-lg border p-6 text-center"
                  >
                    <div className="bg-linear-purple/10 mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-lg">
                      <IconComponent className="text-linear-purple h-6 w-6" />
                    </div>
                    <h3 className="text-linear-text mb-2 text-lg font-semibold">{value.title}</h3>
                    <p className="text-linear-text-secondary text-sm leading-relaxed">
                      {value.description}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>

        {/* Open Positions */}
        <section id="open-positions" className="py-20">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <h2 className="text-linear-text mb-4 text-3xl font-bold sm:text-4xl">
                Open Positions
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                We&apos;re looking for passionate people to join our mission. All positions are
                remote-first.
              </p>
            </div>

            <Card className="border-linear-border bg-linear-card">
              <CardContent className="py-16 text-center">
                <div className="bg-linear-purple/10 mx-auto mb-6 flex h-16 w-16 items-center justify-center rounded-full">
                  <Briefcase className="text-linear-purple/60 h-8 w-8" />
                </div>
                <h3 className="text-linear-text mb-3 text-xl font-semibold">No Open Positions</h3>
                <p className="text-linear-text-secondary mx-auto mb-6 max-w-md">
                  We don&apos;t have any open positions at the moment, but we&apos;re always
                  interested in hearing from talented people who share our passion for health
                  technology.
                </p>
                <Button
                  onClick={() => handleApply('General Application')}
                  variant="outline"
                  className="border-linear-border text-linear-text hover:bg-linear-border/30"
                >
                  <Mail className="mr-2 h-4 w-4" />
                  Send General Application
                </Button>
              </CardContent>
            </Card>

            {/* No Perfect Match CTA */}
            <div className="mt-16 text-center">
              <Card className="border-linear-border bg-linear-card/50">
                <CardHeader>
                  <CardTitle className="text-linear-text text-xl">
                    Don&apos;t see a perfect match?
                  </CardTitle>
                  <CardDescription className="text-linear-text-secondary">
                    We&apos;re always looking for talented people who share our passion for health
                    technology. Send us your resume and tell us how you&apos;d like to contribute.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <Button
                    onClick={() => handleApply('General Application')}
                    variant="outline"
                    className="border-linear-border text-linear-text hover:bg-linear-border/30"
                  >
                    <Mail className="mr-2 h-4 w-4" />
                    Send General Application
                  </Button>
                </CardContent>
              </Card>
            </div>
          </div>
        </section>

        {/* Benefits & Perks */}
        <section className="bg-linear-card/30 py-20">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-16 text-center">
              <h2 className="text-linear-text mb-4 text-3xl font-bold sm:text-4xl">
                Benefits & Perks
              </h2>
              <p className="text-linear-text-secondary mx-auto max-w-2xl text-lg">
                We believe in taking care of our team so they can do their best work.
              </p>
            </div>

            <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
              {benefits.map((benefit, index) => {
                const IconComponent = benefit.icon;
                return (
                  <div
                    key={index}
                    className="border-linear-border bg-linear-bg rounded-lg border p-6"
                  >
                    <div className="bg-linear-purple/10 mb-4 flex h-12 w-12 items-center justify-center rounded-lg">
                      <IconComponent className="text-linear-purple h-6 w-6" />
                    </div>
                    <h3 className="text-linear-text mb-2 text-lg font-semibold">{benefit.title}</h3>
                    <p className="text-linear-text-secondary text-sm leading-relaxed">
                      {benefit.description}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className="py-20">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-4xl text-center">
              <h2 className="text-linear-text mb-6 text-4xl font-bold tracking-tight sm:text-5xl">
                Ready to make an impact?
              </h2>
              <p className="text-linear-text-secondary mx-auto mb-8 max-w-2xl text-lg">
                Join us in building the future of health tracking. Help millions of people
                understand their bodies and achieve their fitness goals.
              </p>

              <div className="flex flex-col justify-center gap-4 sm:flex-row">
                <Button
                  className="bg-linear-text text-linear-bg hover:bg-linear-text-secondary rounded-xl px-8 py-4 text-base font-medium shadow-lg transition-all duration-200 hover:scale-105"
                  onClick={() =>
                    document
                      .getElementById('open-positions')
                      ?.scrollIntoView({ behavior: 'smooth' })
                  }
                >
                  Browse Positions
                </Button>
                <Button
                  variant="ghost"
                  className="border-linear-border/50 text-linear-text-secondary hover:bg-linear-border/30 hover:text-linear-text rounded-xl border px-8 py-4 text-base backdrop-blur-sm transition-all"
                  onClick={() => window.open(`mailto:${logYourBody.contacts.careers}`, '_blank')}
                >
                  <Mail className="mr-2 h-4 w-4" />
                  Get in Touch
                </Button>
              </div>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
