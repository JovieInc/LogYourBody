import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { MesocycleCanvasBoard } from '@/components/training/MesocycleCanvasBoard';
import {
  mesocycleCanvasEnabled,
  mesocycleCanvasFixtureEnabled,
} from '@/lib/flags/mesocycle-canvas';

export const dynamic = 'force-dynamic';

export const metadata: Metadata = {
  title: 'Training plan',
  robots: { index: false, follow: false },
};

export default async function MesocycleCanvasPage() {
  if (!mesocycleCanvasEnabled()) notFound();
  if (mesocycleCanvasFixtureEnabled()) return <MesocycleCanvasBoard mode="fixture" />;
  const { userId } = await getServerAuthSession();
  if (!userId) notFound();
  return <MesocycleCanvasBoard key={userId} mode="account" accountSubject={userId} />;
}
