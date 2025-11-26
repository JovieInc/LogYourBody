'use client'

import React, { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import {
  Shield,
  Info,
  Bug,
  Eye,
  Lock,
  Mail,
  Github,
  CheckCircle,
  Clock,
} from "lucide-react";
import { cn } from "@/lib/utils";

export default function SecurityPage() {
  const [formData, setFormData] = useState({
    reporterName: "",
    reporterEmail: "",
    vulnerabilityType: "other",
    severity: "medium",
    title: "",
    description: "",
    stepsToReproduce: "",
    impact: "",
    suggestedFix: "",
    contactConsent: true,
  });
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const vulnerabilityTypes = [
    { value: "xss", label: "Cross-Site Scripting (XSS)", color: "text-red-600" },
    { value: "sql", label: "SQL Injection", color: "text-red-600" },
    { value: "auth", label: "Authentication Bypass", color: "text-red-600" },
    { value: "data", label: "Data Exposure", color: "text-orange-600" },
    { value: "csrf", label: "Cross-Site Request Forgery", color: "text-orange-600" },
    { value: "dos", label: "Denial of Service", color: "text-yellow-600" },
    { value: "privacy", label: "Privacy Issue", color: "text-blue-600" },
    { value: "other", label: "Other Security Issue", color: "text-gray-600" },
  ];

  const severityLevels = [
    { value: "critical", label: "Critical", description: "Immediate threat to user data or system integrity", color: "bg-red-100 text-red-800 border-red-200" },
    { value: "high", label: "High", description: "Significant security risk requiring urgent attention", color: "bg-orange-100 text-orange-800 border-orange-200" },
    { value: "medium", label: "Medium", description: "Moderate security risk", color: "bg-yellow-100 text-yellow-800 border-yellow-200" },
    { value: "low", label: "Low", description: "Minor security concern", color: "bg-blue-100 text-blue-800 border-blue-200" },
  ];

  const handleInputChange = (field: string, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);

    // Simulate form submission
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    setSubmitted(true);
    setIsSubmitting(false);
  };

  const securityFeatures = [
    {
      icon: Lock,
      title: "End-to-End Encryption",
      description: "All personal health data is encrypted both in transit and at rest using industry-standard AES-256 encryption.",
      bgColor: "bg-blue-100",
      iconColor: "text-blue-600",
    },
    {
      icon: Eye,
      title: "Privacy by Design",
      description: "We collect only the minimum data necessary and give you full control over your information.",
      bgColor: "bg-purple-100",
      iconColor: "text-purple-600",
    },
    {
      icon: Shield,
      title: "Regular Security Audits",
      description: "Our systems undergo regular security assessments and penetration testing by third-party experts.",
      bgColor: "bg-orange-100",
      iconColor: "text-orange-600",
    },
    {
      icon: CheckCircle,
      title: "SOC 2 Compliance",
      description: "We maintain SOC 2 Type II compliance for security, availability, and confidentiality.",
      bgColor: "bg-green-100",
      iconColor: "text-green-600",
    },
  ];

  if (submitted) {
    return (
      <div className="min-h-svh bg-linear-bg font-inter">
        <Header />
        <div className="flex items-center justify-center py-16">
          <div className="container mx-auto px-4 sm:px-6">
            <Card className="mx-auto max-w-2xl border-green-200 bg-green-50">
              <CardHeader className="text-center">
                <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-100">
                  <CheckCircle className="h-8 w-8 text-green-600" />
                </div>
                <CardTitle className="text-2xl text-green-800">Report Submitted Successfully</CardTitle>
                <CardDescription className="text-green-700">
                  Thank you for helping us keep LogYourBody secure.
                </CardDescription>
              </CardHeader>
              <CardContent className="text-center space-y-4">
                <p className="text-green-700">
                  We have received your security report and will investigate it promptly. 
                  Our security team typically responds within 24-48 hours.
                </p>
                <div className="bg-green-100 rounded-lg p-4">
                  <p className="text-sm text-green-800">
                    <strong>Report ID:</strong> SEC-{Date.now().toString().slice(-6)}
                  </p>
                  <p className="text-sm text-green-700 mt-1">
                    Please save this ID for your records. We&apos;ll reference it in our communications.
                  </p>
                </div>
                <Button
                  onClick={() => window.location.href = "/"}
                  className="bg-green-600 text-white hover:bg-green-700"
                >
                  Return to Home
                </Button>
              </CardContent>
            </Card>
          </div>
        </div>
        <Footer />
      </div>
    );
  }

  return (
    <div className="min-h-svh bg-linear-bg font-inter">
      <Header />

      <main>
        {/* Hero Section */}
        <section className="py-16 md:py-24">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mx-auto max-w-4xl text-center">
              <Badge className="mb-6 bg-red-100 text-red-800 border-red-200 inline-block">
                Security & Vulnerability Reporting
              </Badge>
              <h1 className="mb-6 text-4xl sm:text-5xl md:text-6xl font-bold tracking-tight text-linear-text">
                Report a Security
                <br />
                <span className="bg-gradient-to-r from-red-600 via-red-500 to-orange-500 bg-clip-text text-transparent">
                  Vulnerability
                </span>
              </h1>
              <p className="mx-auto mb-8 max-w-2xl text-lg text-linear-text-secondary">
                Help us keep LogYourBody secure. If you&apos;ve discovered a security vulnerability, 
                please report it responsibly through this form.
              </p>
              
              {/* Security Promise */}
              <div className="bg-linear-card/50 border border-linear-border rounded-xl p-6 mb-12">
                <div className="flex items-center justify-center gap-3 mb-4">
                  <Shield className="h-6 w-6 text-green-600" />
                  <h3 className="text-lg font-semibold text-linear-text">Our Security Commitment</h3>
                </div>
                <p className="text-sm text-linear-text-secondary">
                  We take security seriously and appreciate responsible disclosure. Valid reports will be 
                  acknowledged within 24 hours and resolved based on severity level.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Main Form Section */}
        <section className="py-12">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="grid gap-12 lg:grid-cols-3">
              {/* Form */}
              <div className="lg:col-span-2">
                <Card className="border-linear-border bg-linear-card">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-linear-text">
                      <Bug className="h-5 w-5 text-red-600" />
                      Vulnerability Report Form
                    </CardTitle>
                    <CardDescription className="text-linear-text-secondary">
                      Please provide as much detail as possible to help us understand and resolve the issue.
                    </CardDescription>
                  </CardHeader>
                  <CardContent>
                    <form onSubmit={handleSubmit} className="space-y-8">
                      {/* Reporter Information */}
                      <div className="space-y-4">
                        <h3 className="text-lg font-semibold text-linear-text">Reporter Information</h3>
                        <div className="grid gap-4 sm:grid-cols-2">
                          <div>
                            <Label htmlFor="reporterName" className="text-linear-text">Name (Optional)</Label>
                            <Input
                              id="reporterName"
                              value={formData.reporterName}
                              onChange={(e) => handleInputChange("reporterName", e.target.value)}
                              placeholder="Your name"
                              className="mt-1 bg-linear-bg border-linear-border text-linear-text"
                            />
                          </div>
                          <div>
                            <Label htmlFor="reporterEmail" className="text-linear-text">Email</Label>
                            <Input
                              id="reporterEmail"
                              type="email"
                              value={formData.reporterEmail}
                              onChange={(e) => handleInputChange("reporterEmail", e.target.value)}
                              placeholder="your.email@example.com"
                              className="mt-1 bg-linear-bg border-linear-border text-linear-text"
                              required
                            />
                          </div>
                        </div>
                      </div>

                      {/* Vulnerability Type */}
                      <div className="space-y-4">
                        <Label className="text-linear-text">Vulnerability Type</Label>
                        <div className="grid gap-3 sm:grid-cols-2">
                          {vulnerabilityTypes.map((type) => (
                            <div key={type.value}>
                              <label className={cn(
                                "cursor-pointer rounded-lg border p-3 transition-all flex items-center gap-2",
                                formData.vulnerabilityType === type.value ? "border-linear-purple bg-linear-purple/5" : "border-linear-border hover:border-linear-border"
                              )}>
                                <input
                                  type="radio"
                                  name="vulnerabilityType"
                                  value={type.value}
                                  checked={formData.vulnerabilityType === type.value}
                                  onChange={(e) => handleInputChange("vulnerabilityType", e.target.value)}
                                  className="text-linear-purple"
                                />
                                <span className={cn("text-sm font-medium", type.color)}>{type.label}</span>
                              </label>
                            </div>
                          ))}
                        </div>
                      </div>

                      {/* Severity Level */}
                      <div className="space-y-4">
                        <Label className="text-linear-text">Severity Level</Label>
                        <div className="space-y-3">
                          {severityLevels.map((level) => (
                            <label 
                              key={level.value} 
                              htmlFor={`severity-${level.value}`}
                              className={cn(
                                "cursor-pointer rounded-lg border p-4 transition-all flex items-start gap-3",
                                formData.severity === level.value ? "border-linear-purple bg-linear-purple/5" : "border-linear-border hover:border-linear-border"
                              )}>
                              <input
                                id={`severity-${level.value}`}
                                type="radio"
                                name="severity"
                                value={level.value}
                                checked={formData.severity === level.value}
                                onChange={(e) => handleInputChange("severity", e.target.value)}
                                className="mt-0.5 text-linear-purple"
                              />
                              <div className="flex-1">
                                <div className="flex items-center gap-2 mb-1">
                                  <span className="font-medium text-linear-text">{level.label}</span>
                                  <Badge className={level.color}>{level.label}</Badge>
                                </div>
                                <p className="text-sm text-linear-text-secondary">{level.description}</p>
                              </div>
                            </label>
                          ))}
                        </div>
                      </div>

                      {/* Vulnerability Details */}
                      <div className="space-y-4">
                        <h3 className="text-lg font-semibold text-linear-text">Vulnerability Details</h3>
                        
                        <div>
                          <Label htmlFor="title" className="text-linear-text">Title</Label>
                          <Input
                            id="title"
                            value={formData.title}
                            onChange={(e) => handleInputChange("title", e.target.value)}
                            placeholder="Brief description of the vulnerability"
                            className="mt-1 bg-linear-bg border-linear-border text-linear-text"
                            required
                          />
                        </div>

                        <div>
                          <Label htmlFor="description" className="text-linear-text">Description</Label>
                          <Textarea
                            id="description"
                            value={formData.description}
                            onChange={(e) => handleInputChange("description", e.target.value)}
                            placeholder="Detailed description of the vulnerability..."
                            className="mt-1 min-h-[100px] bg-linear-bg border-linear-border text-linear-text"
                            required
                          />
                        </div>

                        <div>
                          <Label htmlFor="stepsToReproduce" className="text-linear-text">Steps to Reproduce</Label>
                          <Textarea
                            id="stepsToReproduce"
                            value={formData.stepsToReproduce}
                            onChange={(e) => handleInputChange("stepsToReproduce", e.target.value)}
                            placeholder="1. Go to...&#10;2. Click on...&#10;3. Enter...&#10;4. Observe..."
                            className="mt-1 min-h-[100px] bg-linear-bg border-linear-border text-linear-text"
                            required
                          />
                        </div>

                        <div>
                          <Label htmlFor="impact" className="text-linear-text">Impact</Label>
                          <Textarea
                            id="impact"
                            value={formData.impact}
                            onChange={(e) => handleInputChange("impact", e.target.value)}
                            placeholder="What is the potential impact of this vulnerability?"
                            className="mt-1 bg-linear-bg border-linear-border text-linear-text"
                            required
                          />
                        </div>

                        <div>
                          <Label htmlFor="suggestedFix" className="text-linear-text">Suggested Fix (Optional)</Label>
                          <Textarea
                            id="suggestedFix"
                            value={formData.suggestedFix}
                            onChange={(e) => handleInputChange("suggestedFix", e.target.value)}
                            placeholder="Any suggestions for fixing this vulnerability..."
                            className="mt-1 bg-linear-bg border-linear-border text-linear-text"
                          />
                        </div>
                      </div>

                      {/* Consent */}
                      <div className="space-y-4">
                        <div className="flex items-start gap-3">
                          <input
                            type="checkbox"
                            id="contactConsent"
                            checked={formData.contactConsent}
                            onChange={(e) => handleInputChange("contactConsent", e.target.checked)}
                            className="mt-1"
                          />
                          <Label htmlFor="contactConsent" className="text-sm leading-relaxed text-linear-text">
                            I consent to being contacted regarding this vulnerability report and understand that 
                            my information will be handled according to LogYourBody&apos;s privacy policy.
                          </Label>
                        </div>
                      </div>

                      {/* Submit Button */}
                      <Button
                        type="submit"
                        disabled={isSubmitting || !formData.contactConsent}
                        className="w-full bg-red-600 text-white hover:bg-red-700 disabled:opacity-50"
                      >
                        {isSubmitting ? (
                          <div className="flex items-center gap-2">
                            <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-r-transparent" />
                            Submitting Report...
                          </div>
                        ) : (
                          "Submit Security Report"
                        )}
                      </Button>
                    </form>
                  </CardContent>
                </Card>
              </div>

              {/* Sidebar */}
              <div className="space-y-6">
                {/* Guidelines */}
                <Card className="border-linear-border bg-linear-card">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-lg text-linear-text">
                      <Info className="h-5 w-5 text-blue-600" />
                      Reporting Guidelines
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-4 text-sm">
                    <div>
                      <h4 className="font-medium text-linear-text mb-1">✅ Do</h4>
                      <ul className="text-linear-text-secondary space-y-1">
                        <li>• Provide detailed reproduction steps</li>
                        <li>• Include impact assessment</li>
                        <li>• Test in a safe environment</li>
                        <li>• Report promptly after discovery</li>
                      </ul>
                    </div>
                    <div>
                      <h4 className="font-medium text-linear-text mb-1">❌ Don&apos;t</h4>
                      <ul className="text-linear-text-secondary space-y-1">
                        <li>• Access user data without permission</li>
                        <li>• Perform destructive testing</li>
                        <li>• Publicly disclose before resolution</li>
                        <li>• Spam our systems</li>
                      </ul>
                    </div>
                  </CardContent>
                </Card>

                {/* Response Times */}
                <Card className="border-linear-border bg-linear-card">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-lg text-linear-text">
                      <Clock className="h-5 w-5 text-blue-600" />
                      Response Timeline
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-3 text-sm">
                    <div className="flex justify-between">
                      <span className="text-linear-text-secondary">Acknowledgment:</span>
                      <span className="font-medium text-linear-text">24-48 hours</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-linear-text-secondary">Critical issues:</span>
                      <span className="font-medium text-linear-text">1-3 days</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-linear-text-secondary">High severity:</span>
                      <span className="font-medium text-linear-text">1-2 weeks</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-linear-text-secondary">Medium/Low:</span>
                      <span className="font-medium text-linear-text">2-4 weeks</span>
                    </div>
                  </CardContent>
                </Card>

                {/* Contact Info */}
                <Card className="border-linear-border bg-linear-card">
                  <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-lg text-linear-text">
                      <Mail className="h-5 w-5 text-blue-600" />
                      Alternative Contact
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-4 text-sm">
                    <p className="text-linear-text-secondary">
                      For urgent security issues, you can also reach us directly:
                    </p>
                    <div className="space-y-2">
                      <div className="flex items-center gap-2">
                        <Mail className="h-4 w-4 text-linear-text-secondary" />
                        <span className="text-linear-text">security@logyourbody.com</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <Github className="h-4 w-4 text-linear-text-secondary" />
                        <a 
                          href="https://github.com/JovieInc/LogYourBody/security"
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-linear-purple hover:underline"
                        >
                          GitHub Security
                        </a>
                      </div>
                    </div>
                  </CardContent>
                </Card>
              </div>
            </div>
          </div>
        </section>

        {/* Security Features */}
        <section className="py-16 bg-linear-card/30">
          <div className="container mx-auto px-4 sm:px-6">
            <div className="mb-12 text-center">
              <h2 className="mb-4 text-3xl sm:text-4xl font-bold text-linear-text">
                Our Security Measures
              </h2>
              <p className="mx-auto max-w-2xl text-lg text-linear-text-secondary">
                We implement multiple layers of security to protect your data and privacy.
              </p>
            </div>

            <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-4">
              {securityFeatures.map((feature, index) => {
                const IconComponent = feature.icon;
                return (
                  <div
                    key={index}
                    className="rounded-lg border border-linear-border bg-linear-bg p-6 text-center"
                  >
                    <div className={`mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-lg ${feature.bgColor}`}>
                      <IconComponent className={`h-6 w-6 ${feature.iconColor}`} />
                    </div>
                    <h3 className="mb-2 text-lg font-semibold text-linear-text">
                      {feature.title}
                    </h3>
                    <p className="text-sm text-linear-text-secondary leading-relaxed">
                      {feature.description}
                    </p>
                  </div>
                );
              })}
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}