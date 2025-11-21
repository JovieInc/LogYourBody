'use client'

import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Input } from '@/components/ui/input'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Separator } from '@/components/ui/separator'
import { toast } from '@/hooks/use-toast'
import {
  Loader2,
  ArrowLeft,
  Mail,
  Save,
  Info
} from 'lucide-react'
import Link from 'next/link'

export default function NotificationsSettingsPage() {
  const { user, loading } = useAuth()
  const router = useRouter()
  const [isSaving, setIsSaving] = useState(false)
  const [hasChanges, setHasChanges] = useState(false)

  const [settings, setSettings] = useState({
    push_notifications: {
      enabled: true,
      daily_reminder: true,
      reminder_time: '09:00',
      weekly_summary: true,
      goal_achievements: true,
      tips_and_insights: false
    },
    email_notifications: {
      weekly_report: true,
      monthly_summary: true,
      product_updates: true,
      marketing_emails: false
    },
    reminder_settings: {
      reminder_days: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
      snooze_duration: '30' // minutes
    }
  })

  useEffect(() => {
    if (!loading && !user) {
      router.push('/signin')
    }
  }, [user, loading, router])

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-linear-bg">
        <Loader2 className="h-8 w-8 animate-spin text-linear-text-secondary" />
      </div>
    )
  }

  if (!user) {
    return null
  }

  const primaryEmail = user.primaryEmailAddress?.emailAddress
    ?? user.emailAddresses?.[0]?.emailAddress
    ?? ''

  const updateSettings = (category: string, setting: string, value: boolean | string | string[]) => {
    setSettings(prev => ({
      ...prev,
      [category]: {
        ...prev[category as keyof typeof prev],
        [setting]: value
      }
    }))
    setHasChanges(true)
  }

  const toggleReminderDay = (day: string) => {
    const days = settings.reminder_settings.reminder_days
    const newDays = days.includes(day)
      ? days.filter(d => d !== day)
      : [...days, day]

    updateSettings('reminder_settings', 'reminder_days', newDays)
  }

  const handleSave = async () => {
    setIsSaving(true)
    try {
      await new Promise(resolve => setTimeout(resolve, 1000))
      toast({
        title: "Notifications updated",
        description: "Your notification preferences have been saved."
      })
      setHasChanges(false)
    } catch {
      toast({
        title: "Error",
        description: "Failed to save notification settings. Please try again.",
        variant: "destructive"
      })
    } finally {
      setIsSaving(false)
    }
  }

  const DAYS = [
    { value: 'mon', label: 'M' },
    { value: 'tue', label: 'T' },
    { value: 'wed', label: 'W' },
    { value: 'thu', label: 'T' },
    { value: 'fri', label: 'F' },
    { value: 'sat', label: 'S' },
    { value: 'sun', label: 'S' }
  ]

  return (
    <div className="min-h-screen bg-linear-bg">
      {/* Header */}
      <header className="bg-linear-card shadow-sm border-b border-linear-border sticky top-0 z-10">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/settings">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-xl font-bold text-linear-text">Notifications</h1>
            </div>
            {hasChanges && (
              <Button
                onClick={handleSave}
                disabled={isSaving}
                size="sm"
                className="bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                {isSaving ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Save className="h-4 w-4" />
                )}
              </Button>
            )}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-2xl space-y-6">
        {/* Push Notifications */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <div className="flex items-center justify-between">
              <div>
                <CardTitle className="text-linear-text">Push Notifications</CardTitle>
                <CardDescription className="text-linear-text-secondary">
                  Get reminders and updates on your device
                </CardDescription>
              </div>
              <Switch
                checked={settings.push_notifications.enabled}
                onCheckedChange={(checked) => updateSettings('push_notifications', 'enabled', checked)}
              />
            </div>
          </CardHeader>
          {settings.push_notifications.enabled && (
            <CardContent className="space-y-6">
              {/* Daily Reminder */}
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label htmlFor="dailyReminder" className="text-linear-text font-normal">
                      Daily Reminder
                    </Label>
                    <p className="text-sm text-linear-text-secondary">
                      Get reminded to log your daily metrics
                    </p>
                  </div>
                  <Switch
                    id="dailyReminder"
                    checked={settings.push_notifications.daily_reminder}
                    onCheckedChange={(checked) => updateSettings('push_notifications', 'daily_reminder', checked)}
                  />
                </div>

                {settings.push_notifications.daily_reminder && (
                  <div className="ml-6 space-y-3">
                    <div className="space-y-2">
                      <Label htmlFor="reminderTime" className="text-sm text-linear-text">
                        Reminder Time
                      </Label>
                      <Input
                        id="reminderTime"
                        type="time"
                        value={settings.push_notifications.reminder_time}
                        onChange={(e) => updateSettings('push_notifications', 'reminder_time', e.target.value)}
                        className="bg-linear-bg border-linear-border text-linear-text max-w-xs"
                      />
                    </div>

                    <div className="space-y-2">
                      <Label className="text-sm text-linear-text">
                        Reminder Days
                      </Label>
                      <div className="flex gap-2">
                        {DAYS.map((day) => (
                          <button
                            key={day.value}
                            onClick={() => toggleReminderDay(day.value)}
                            className={`
                              h-10 w-10 rounded-lg border-2 text-sm font-medium transition-colors
                              ${settings.reminder_settings.reminder_days.includes(day.value)
                                ? 'border-linear-purple bg-linear-purple/10 text-linear-text'
                                : 'border-linear-border text-linear-text-tertiary hover:border-linear-text-tertiary'
                              }
                            `}
                          >
                            {day.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  </div>
                )}
              </div>

              <Separator className="bg-linear-border" />

              {/* Weekly Summary */}
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="weeklySummary" className="text-linear-text font-normal">
                    Weekly Summary
                  </Label>
                  <p className="text-sm text-linear-text-secondary">
                    Review your progress every Sunday
                  </p>
                </div>
                <Switch
                  id="weeklySummary"
                  checked={settings.push_notifications.weekly_summary}
                  onCheckedChange={(checked) => updateSettings('push_notifications', 'weekly_summary', checked)}
                />
              </div>

              <Separator className="bg-linear-border" />

              {/* Goal Achievements */}
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="goalAchievements" className="text-linear-text font-normal">
                    Goal Achievements
                  </Label>
                  <p className="text-sm text-linear-text-secondary">
                    Celebrate when you reach milestones
                  </p>
                </div>
                <Switch
                  id="goalAchievements"
                  checked={settings.push_notifications.goal_achievements}
                  onCheckedChange={(checked) => updateSettings('push_notifications', 'goal_achievements', checked)}
                />
              </div>

              <Separator className="bg-linear-border" />

              {/* Tips & Insights */}
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label htmlFor="tipsInsights" className="text-linear-text font-normal">
                    Tips & Insights
                  </Label>
                  <p className="text-sm text-linear-text-secondary">
                    Personalized recommendations
                  </p>
                </div>
                <Switch
                  id="tipsInsights"
                  checked={settings.push_notifications.tips_and_insights}
                  onCheckedChange={(checked) => updateSettings('push_notifications', 'tips_and_insights', checked)}
                />
              </div>
            </CardContent>
          )}
        </Card>

        {/* Email Notifications */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Email Notifications</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Manage email communications
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            <Alert className="border-linear-border bg-linear-card">
              <Mail className="h-4 w-4 text-linear-text" />
              <AlertDescription className="text-linear-text-secondary">
                Emails will be sent to: <strong className="text-linear-text">{primaryEmail}</strong>
              </AlertDescription>
            </Alert>

            {/* Weekly Report */}
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label htmlFor="weeklyReport" className="text-linear-text font-normal">
                  Weekly Progress Report
                </Label>
                <p className="text-sm text-linear-text-secondary">
                  Detailed summary of your week
                </p>
              </div>
              <Switch
                id="weeklyReport"
                checked={settings.email_notifications.weekly_report}
                onCheckedChange={(checked) => updateSettings('email_notifications', 'weekly_report', checked)}
              />
            </div>

            <Separator className="bg-linear-border" />

            {/* Monthly Summary */}
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label htmlFor="monthlySummary" className="text-linear-text font-normal">
                  Monthly Summary
                </Label>
                <p className="text-sm text-linear-text-secondary">
                  Long-term trends and insights
                </p>
              </div>
              <Switch
                id="monthlySummary"
                checked={settings.email_notifications.monthly_summary}
                onCheckedChange={(checked) => updateSettings('email_notifications', 'monthly_summary', checked)}
              />
            </div>

            <Separator className="bg-linear-border" />

            {/* Product Updates */}
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label htmlFor="productUpdates" className="text-linear-text font-normal">
                  Product Updates
                </Label>
                <p className="text-sm text-linear-text-secondary">
                  New features and improvements
                </p>
              </div>
              <Switch
                id="productUpdates"
                checked={settings.email_notifications.product_updates}
                onCheckedChange={(checked) => updateSettings('email_notifications', 'product_updates', checked)}
              />
            </div>

            <Separator className="bg-linear-border" />

            {/* Marketing Emails */}
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <Label htmlFor="marketingEmails" className="text-linear-text font-normal">
                  Marketing Emails
                </Label>
                <p className="text-sm text-linear-text-secondary">
                  Tips, offers, and promotions
                </p>
              </div>
              <Switch
                id="marketingEmails"
                checked={settings.email_notifications.marketing_emails}
                onCheckedChange={(checked) => updateSettings('email_notifications', 'marketing_emails', checked)}
              />
            </div>
          </CardContent>
        </Card>

        {/* Quiet Hours */}
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Quiet Hours</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Pause notifications during specific times
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Alert className="border-linear-border bg-linear-card">
              <Info className="h-4 w-4 text-linear-text" />
              <AlertDescription className="text-linear-text-secondary">
                Quiet hours respect your device's Do Not Disturb settings
              </AlertDescription>
            </Alert>
          </CardContent>
        </Card>
      </main>
    </div>
  )
}