import { NextRequest, NextResponse } from 'next/server'
import { auth } from '@clerk/nextjs/server'
import {
  fetchBodyspecScans,
  BodyspecRequestError,
  type BodyspecAuthSession,
} from '../../../../../../../tools/bodyspec-mcp'

export async function POST(request: NextRequest) {
  try {
    const { userId } = await auth()

    if (!userId) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    let payload: unknown
    try {
      payload = await request.json()
    } catch {
      return NextResponse.json({ error: 'Invalid JSON payload' }, { status: 400 })
    }

    const body = typeof payload === 'object' && payload !== null ? (payload as Record<string, unknown>) : {}

    const email = typeof body.email === 'string' ? body.email.trim() : ''
    const password = typeof body.password === 'string' ? body.password : ''
    const perPage = typeof body.perPage === 'number' ? body.perPage : undefined

    let existingSession: BodyspecAuthSession | undefined

    if (body.session && typeof body.session === 'object' && body.session !== null) {
      const sessionCandidate = body.session as Record<string, unknown>
      if (typeof sessionCandidate.accessToken === 'string' && typeof sessionCandidate.client === 'string' && typeof sessionCandidate.uid === 'string') {
        existingSession = {
          accessToken: sessionCandidate.accessToken,
          client: sessionCandidate.client,
          uid: sessionCandidate.uid,
          expiry: typeof sessionCandidate.expiry === 'string' ? sessionCandidate.expiry : undefined,
          tokenType: typeof sessionCandidate.tokenType === 'string' ? sessionCandidate.tokenType : undefined,
        }
      }
    }

    if ((!email || !password) && !existingSession) {
      return NextResponse.json(
        {
          error: 'BodySpec credentials are required',
        },
        { status: 400 }
      )
    }

    const { scans, session } = await fetchBodyspecScans({
      credentials: existingSession ? undefined : { email, password },
      session: existingSession,
      perPage,
    })

    return NextResponse.json({
      scans,
      meta: {
        count: scans.length,
      },
      session,
    })
  } catch (error) {
    if (error instanceof BodyspecRequestError) {
      return NextResponse.json(
        {
          error: error.message,
          details: error.details ?? null,
        },
        { status: error.status ?? 500 }
      )
    }

    console.error('BodySpec import error:', error)
    return NextResponse.json({ error: 'Unexpected error connecting to BodySpec' }, { status: 500 })
  }
}
