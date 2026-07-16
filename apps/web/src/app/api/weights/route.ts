import { NextRequest, NextResponse } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { neonBodyMetrics } from '@/lib/neon/body-metrics-adapter';

export async function GET(_request: NextRequest) {
  try {
    const { userId } = await getServerAuthSession();

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const weights = await neonBodyMetrics.list(userId);

    return NextResponse.json({
      weights: weights || [],
    });
  } catch (error) {
    console.error('Error fetching weights:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const { userId } = await getServerAuthSession();

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const { weight, unit, notes } = await request.json();

    if (!weight || !unit) {
      return NextResponse.json({ error: 'Weight and unit are required' }, { status: 400 });
    }

    // Convert to kg if needed
    let weightInKg = parseFloat(weight);
    if (unit === 'lbs') {
      weightInKg = weightInKg * 0.453592;
    }

    const weightEntry = await neonBodyMetrics.upsert(userId, {
      date: new Date().toISOString().slice(0, 10),
      weight: weightInKg,
      weight_unit: 'kg',
      body_fat_percentage: null,
      body_fat_method: null,
      muscle_mass: null,
      waist: null,
      neck: null,
      hip: null,
      notes: typeof notes === 'string' ? notes : null,
      photo_url: null,
      data_source: 'manual',
      source_metadata: {},
    });

    return NextResponse.json({
      success: true,
      weight: weightEntry,
    });
  } catch (error) {
    console.error('Error logging weight:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
