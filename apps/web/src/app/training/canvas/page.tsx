import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
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

export default function MesocycleCanvasPage() {
  if (!mesocycleCanvasEnabled()) notFound();
  return <MesocycleCanvasBoard mode={mesocycleCanvasFixtureEnabled() ? 'fixture' : 'account'} />;
}
