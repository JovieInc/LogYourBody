import { NextRequest, NextResponse } from 'next/server';
import { getServerAuthSession } from '@/lib/ports/server-auth-runtime';
import { createAuthenticatedDataClient } from '@/lib/ports/server-data-client';

export async function GET(_request: NextRequest) {
  try {
    const { userId, getToken } = await getServerAuthSession();

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const supabase = await createAuthenticatedDataClient(getToken);

    // Fetch latest body metrics with weight entries
    const { data: weights, error } = await supabase
      .from('body_metrics')
      .select('*')
      .eq('user_id', userId)
      .order('date', { ascending: false })
      .limit(30);

    if (error) {
      throw error;
    }

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
    const { userId, getToken } = await getServerAuthSession();

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const supabase = await createAuthenticatedDataClient(getToken);

    const { weight, unit, notes } = await request.json();

    if (!weight || !unit) {
      return NextResponse.json({ error: 'Weight and unit are required' }, { status: 400 });
    }

    // Convert to kg if needed
    let weightInKg = parseFloat(weight);
    if (unit === 'lbs') {
      weightInKg = weightInKg * 0.453592;
    }

    // Insert body metrics weight entry
    const { data, error } = await supabase
      .from('body_metrics')
      .insert({
        user_id: userId,
        date: new Date().toISOString(),
        weight: weightInKg,
        weight_unit: 'kg',
        notes,
      })
      .select()
      .single();

    if (error) {
      throw error;
    }

    return NextResponse.json({
      success: true,
      weight: data,
    });
  } catch (error) {
    console.error('Error logging weight:', error);
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 });
  }
}
