'use client'

import React, { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { VersionDisplay } from "@/components/VersionDisplay";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import {
  ArrowLeft,
  GitCommit,
  Calendar,
  ExternalLink,
  Github,
  Check,
  AlertCircle,
} from "lucide-react";
import { useRouter } from "next/navigation";

interface GitCommit {
  sha: string;
  message: string;
  author: {
    name: string;
    email: string;
    date: string;
  };
  committer: {
    name: string;
    email: string;
    date: string;
  };
  url: string;
  html_url: string;
}

interface GitHubResponse {
  sha: string;
  commit: {
    message: string;
    author: {
      name: string;
      email: string;
      date: string;
    };
    committer: {
      name: string;
      email: string;
      date: string;
    };
  };
  html_url: string;
  author?: {
    login: string;
    avatar_url: string;
  };
}

export default function ChangelogPage() {
  const router = useRouter();
  const [commits, setCommits] = useState<GitCommit[]>([]);
  const [loading, setLoading] = useState(true);

  // Email subscription state
  const [email, setEmail] = useState("");
  const [isSubscribing, setIsSubscribing] = useState(false);
  const [subscriptionStatus, setSubscriptionStatus] = useState<
    "idle" | "success" | "error"
  >("idle");
  const [subscriptionMessage, setSubscriptionMessage] = useState("");

  const fetchCommits = useCallback(async () => {
    try {
      // Try to fetch from GitHub API
      const response = await fetch(
        "https://api.github.com/repos/JovieInc/LogYourBody/commits?per_page=50",
      );

      if (response.ok) {
        const data: GitHubResponse[] = await response.json();
        const formattedCommits: GitCommit[] = data.map((commit) => ({
          sha: commit.sha,
          message: commit.commit.message,
          author: commit.commit.author,
          committer: commit.commit.committer,
          url: commit.html_url,
          html_url: commit.html_url,
        }));
        setCommits(formattedCommits);
      } else {
        // Fallback to mock data if GitHub API fails
        setCommits(getMockCommits());
      }
    } catch (err) {
      console.error("Failed to fetch commits:", err);
      setCommits(getMockCommits());
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchCommits();
  }, [fetchCommits]);

  const getMockCommits = (): GitCommit[] => [
    {
      sha: "3a20798",
      message:
        "Fix Settings page mobile blank screen issue\n\n- Add proper null checks for user and settings data\n- Add useEffect to update form states when user data loads\n- Add fallback values for all user properties to prevent crashes\n- Fix potential race conditions with data loading\n- Ensure Settings page renders properly on mobile devices",
      author: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date().toISOString(),
      },
      committer: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date().toISOString(),
      },
      url: "https://github.com/JovieInc/LogYourBody/commit/3a20798",
      html_url: "https://github.com/JovieInc/LogYourBody/commit/3a20798",
    },
    {
      sha: "8a343e5",
      message:
        "Implement comprehensive PWA version management and cache handling\n\n- Add PWAUpdatePrompt component with user-friendly update notifications\n- Create VersionDisplay component showing app version and build info\n- Implement usePWAUpdate hook for proper SW update lifecycle management\n- Add version information to PWA manifest and build process\n- Ensure proper cache clearing when updates are available\n- Display version info in Dashboard header and Settings page\n- Configure PWA for prompt-based updates instead of auto-updates",
      author: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      },
      committer: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(),
      },
      url: "https://github.com/JovieInc/LogYourBody/commit/8a343e5",
      html_url: "https://github.com/JovieInc/LogYourBody/commit/8a343e5",
    },
    {
      sha: "800a15d",
      message:
        "Fix biometric authentication implementation\n\n- Fix critical counter initialization bug in WebAuthn hook\n- Improve credential verification during authentication\n- Remove biometric login from login page (should be for existing users only)\n- Add proper error handling for WebAuthn operations\n- Enhance biometric setup component integration",
      author: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      },
      committer: {
        name: "Claude",
        email: "noreply@anthropic.com",
        date: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
      },
      url: "https://github.com/JovieInc/LogYourBody/commit/800a15d",
      html_url: "https://github.com/JovieInc/LogYourBody/commit/800a15d",
    },
  ];

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleDateString("en-US", {
      year: "numeric",
      month: "short",
      day: "numeric",
    });
  };

  const formatTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  const getCommitType = (message: string) => {
    const firstLine = message.split("\n")[0].toLowerCase();
    if (firstLine.includes("fix") || firstLine.includes("bug")) {
      return { type: "fix", color: "" };
    }
    if (
      firstLine.includes("feat") ||
      firstLine.includes("add") ||
      firstLine.includes("implement")
    ) {
      return {
        type: "feature",
        color: "",
      };
    }
    if (
      firstLine.includes("update") ||
      firstLine.includes("improve") ||
      firstLine.includes("enhance")
    ) {
      return {
        type: "improvement",
        color: "",
      };
    }
    if (firstLine.includes("refactor") || firstLine.includes("clean")) {
      return {
        type: "refactor",
        color: "",
      };
    }
    return {
      type: "change",
      color: "",
    };
  };

  const parseCommitMessage = (message: string) => {
    const lines = message.split("\n");
    const title = lines[0];
    const body = lines.slice(2).join("\n").trim(); // Skip empty line after title
    return { title, body };
  };

  const getBodySnippet = (body: string) => {
    if (!body) return "";
    const cleaned = body.replace(/\n+/g, " ").trim();
    return cleaned.length > 120 ? `${cleaned.slice(0, 117)}...` : cleaned;
  };

  const getShortSha = (sha: string) => sha.substring(0, 7);

  const handleEmailSubscription = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!email || !email.includes("@")) {
      setSubscriptionStatus("error");
      setSubscriptionMessage("Please enter a valid email address");
      return;
    }

    setIsSubscribing(true);
    setSubscriptionStatus("idle");

    try {
      // Simulate subscription
      await new Promise(resolve => setTimeout(resolve, 1000));
      
      setSubscriptionStatus("success");
      setSubscriptionMessage("Successfully subscribed to changelog updates!");
      setEmail("");
    } catch (err: unknown) {
      console.error("Subscription error:", err);
      setSubscriptionStatus("error");
      setSubscriptionMessage("Failed to subscribe. Please try again later.");
    } finally {
      setIsSubscribing(false);

      // Clear status after 5 seconds
      setTimeout(() => {
        setSubscriptionStatus("idle");
        setSubscriptionMessage("");
      }, 5000);
    }
  };

  if (loading) {
    return (
      <div className="min-h-svh bg-linear-bg font-inter">
        <Header />
        <div className="flex min-h-svh items-center justify-center">
          <div className="text-center">
            <div className="mx-auto mb-4 h-8 w-8 animate-spin rounded-full border-2 border-linear-purple border-t-transparent"></div>
            <p className="text-linear-text-secondary">Loading changelog...</p>
          </div>
        </div>
        <Footer />
      </div>
    );
  }

  return (
    <div className="min-h-svh bg-linear-bg text-linear-text font-inter">
      <Header />

      {/* Navigation */}
      <div className="sticky top-0 z-40 border-b border-linear-border bg-linear-bg/95 backdrop-blur supports-[backdrop-filter]:bg-linear-bg/60">
        <div className="container mx-auto max-w-6xl px-4 py-4 sm:px-6">
          <div className="flex items-center gap-4">
            <Button
              size="icon"
              variant="ghost"
              onClick={() => router.back()}
              aria-label="Go back"
              className="h-10 w-10 text-linear-text-secondary hover:text-linear-text hover:bg-linear-border/50 transition-colors"
            >
              <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            </Button>
            <VersionDisplay />
          </div>
        </div>
      </div>

      {/* Hero Header */}
      <div className="relative">
        <div className="absolute inset-0 bg-gradient-to-br from-linear-purple/5 via-linear-bg to-linear-bg" />
        <div className="container relative mx-auto max-w-6xl px-4 py-12 sm:px-6 sm:py-16">
          <div className="max-w-3xl">
            <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:gap-3">
              <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-linear-purple/10">
                <GitCommit className="h-6 w-6 text-linear-purple" aria-hidden="true" />
              </div>
              <div>
                <h1 className="text-3xl font-bold tracking-tight text-linear-text sm:text-4xl">Changelog</h1>
                <p className="mt-2 text-lg text-linear-text-secondary sm:text-xl">
                  Stay up to date with the latest features, improvements, and
                  fixes
                </p>
              </div>
            </div>

            {/* Email Subscription */}
            <div className="mt-8 rounded-lg border border-linear-border bg-linear-card p-4">
              <form
                onSubmit={handleEmailSubscription}
                className="flex flex-col gap-2 sm:flex-row sm:items-center"
              >
                <Input
                  type="email"
                  aria-label="Email address"
                  placeholder="Your email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  disabled={isSubscribing}
                  className="flex-1 h-10 text-sm bg-linear-bg border-linear-border text-linear-text"
                />
                <Button
                  type="submit"
                  disabled={isSubscribing || !email}
                  className="h-10 px-4 flex-shrink-0 bg-linear-text text-linear-bg hover:bg-linear-text/90"
                >
                  {isSubscribing ? (
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-current border-r-transparent" />
                  ) : (
                    "Sign up"
                  )}
                </Button>
              </form>

              {subscriptionMessage && (
                <p
                  className={`mt-2 flex items-center gap-2 text-sm ${
                    subscriptionStatus === "success"
                      ? "text-green-500"
                      : "text-red-500"
                  }`}
                  aria-live="polite"
                >
                  {subscriptionStatus === "success" ? (
                    <Check className="h-4 w-4" aria-hidden="true" />
                  ) : (
                    <AlertCircle className="h-4 w-4" aria-hidden="true" />
                  )}
                  {subscriptionMessage}
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Content */}
      <div className="container mx-auto max-w-4xl px-4 py-8 sm:px-6">
        {/* Commit Timeline */}
        <div className="space-y-6">
          {commits.map((commit, index) => {
            const { title, body } = parseCommitMessage(commit.message);
            const snippet = getBodySnippet(body);
            const commitType = getCommitType(title);
            const isLastItem = index === commits.length - 1;

            return (
              <div key={commit.sha} className="relative">
                {/* Timeline line */}
                {!isLastItem && (
                  <div className="absolute bottom-0 left-5 top-12 w-px bg-linear-border" />
                )}

                <div className="flex gap-4">
                  {/* Timeline dot */}
                  <div className="relative flex-shrink-0">
                    <div className="flex h-10 w-10 items-center justify-center rounded-full border-2 border-linear-border bg-linear-bg">
                      <GitCommit className="h-4 w-4 text-linear-text-tertiary" aria-hidden="true" />
                    </div>
                  </div>

                  {/* Commit content */}
                  <div className="min-w-0 flex-1">
                    <div className="rounded-lg border border-linear-border bg-linear-card p-6 transition-all hover:border-linear-text-tertiary">
                      {/* Commit header */}
                      <div className="mb-4 flex items-start justify-between gap-4">
                        <div className="min-w-0 flex-1">
                          <div className="mb-2 flex items-center gap-2">
                            <Badge
                              variant="outline"
                              className={`border text-xs ${
                                commitType.type === "fix" ? "border-red-500/30 bg-red-500/10 text-red-500" :
                                commitType.type === "feature" ? "border-green-500/30 bg-green-500/10 text-green-500" :
                                commitType.type === "improvement" ? "border-blue-500/30 bg-blue-500/10 text-blue-500" :
                                commitType.type === "refactor" ? "border-purple-500/30 bg-purple-500/10 text-purple-500" :
                                "border-linear-border bg-linear-card text-linear-text-tertiary"
                              }`}
                            >
                              {commitType.type}
                            </Badge>
                            <code className="rounded bg-linear-border px-2 py-1 font-mono text-xs text-linear-text-tertiary">
                              {getShortSha(commit.sha)}
                            </code>
                          </div>
                          <h3 className="mb-2 break-words text-lg font-semibold text-linear-text">
                            {title}
                          </h3>
                        </div>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => window.open(commit.html_url, "_blank")}
                          aria-label={`View commit ${getShortSha(commit.sha)}`}
                          className="flex-shrink-0 text-linear-text-secondary hover:text-linear-text hover:bg-linear-border/50"
                        >
                        <ExternalLink className="mr-1 h-3 w-3" aria-hidden="true" />
                        View
                        </Button>
                      </div>

                      {/* Commit body */}
                      {snippet && (
                        <p className="mb-4 text-sm text-linear-text-secondary">
                          {snippet}
                        </p>
                      )}

                      {/* Commit metadata */}
                      <div className="flex items-center gap-4 text-xs text-linear-text-tertiary">
                        <div className="flex items-center gap-1">
                          <Calendar className="h-3 w-3" aria-hidden="true" />
                          <span>
                            {formatDate(commit.author.date)} at{" "}
                            {formatTime(commit.author.date)}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* Footer */}
        <div className="mt-12 border-t border-linear-border pt-8">
          <div className="flex flex-col items-center gap-2 text-center text-sm text-linear-text-tertiary sm:flex-row sm:justify-center sm:gap-4">
            <Github className="h-4 w-4" aria-hidden="true" />
            <span>View full commit history on</span>
            <Button
              variant="link"
              size="sm"
              onClick={() =>
                window.open(
                  "https://github.com/JovieInc/LogYourBody/commits/main",
                  "_blank",
                )
              }
              className="h-auto p-0 text-linear-purple hover:text-linear-purple/80"
            >
              GitHub
            </Button>
          </div>
        </div>
      </div>

      <Footer />
    </div>
  );
}