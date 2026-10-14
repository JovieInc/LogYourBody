import { notFound } from 'next/navigation';
import { mesocycleCanvasEnabled } from '@/lib/flags/mesocycle-canvas';
import { MesocycleCanvasBoard } from './MesocycleCanvasBoard';

export const dynamic = 'force-dynamic';

export function mesocycleCanvasPageGate(
  env: NodeJS.ProcessEnv = process.env,
): 'page' | 'not-found' {
  return mesocycleCanvasEnabled(env) ? 'page' : 'not-found';
}

export default function MesocycleCanvasPage() {
  if (mesocycleCanvasPageGate() === 'not-found') notFound();
  return <MesocycleCanvasBoard />;
}
