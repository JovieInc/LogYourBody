import { URLSearchParams } from 'url'

export interface BodyspecCredentials {
  email: string
  password: string
}

export interface BodyspecAuthSession {
  accessToken: string
  client: string
  uid: string
  expiry?: string
  tokenType?: string
}

export interface NormalizedBodyspecScan {
  date: string
  weight: number | null
  weight_unit: 'lbs' | 'kg'
  body_fat_percentage: number | null
  lean_mass: number | null
  fat_mass: number | null
  bone_mass: number | null
  visceral_fat: number | null
  source: 'BodySpec'
  reference_id?: string | number
  raw?: unknown
}

export class BodyspecRequestError extends Error {
  status?: number
  details?: unknown

  constructor(message: string, options?: { status?: number; details?: unknown }) {
    super(message)
    this.name = 'BodyspecRequestError'
    this.status = options?.status
    this.details = options?.details
  }
}

const DEFAULT_BASE_URL = 'https://prod.bodyspec.com/api/v3'

const numberFallback = (value: unknown): number | null => {
  if (value === null || value === undefined) {
    return null
  }

  if (typeof value === 'number' && !Number.isNaN(value)) {
    return value
  }

  if (typeof value === 'string') {
    const parsed = Number(value.trim())
    return Number.isFinite(parsed) ? parsed : null
  }

  return null
}

const normaliseDate = (value: unknown): string | null => {
  if (typeof value === 'string' && value.trim()) {
    const isoDate = new Date(value)
    if (!Number.isNaN(isoDate.valueOf())) {
      return isoDate.toISOString().slice(0, 10)
    }
  }

  if (typeof value === 'number') {
    const isoDate = new Date(value * 1000)
    if (!Number.isNaN(isoDate.valueOf())) {
      return isoDate.toISOString().slice(0, 10)
    }
  }

  return null
}

const determineWeightUnit = (raw: any): 'lbs' | 'kg' => {
  const unit = raw?.weight_unit || raw?.units?.weight || raw?.weightUnit
  if (typeof unit === 'string') {
    const normalised = unit.toLowerCase()
    if (normalised.includes('kg')) return 'kg'
  }
  return 'lbs'
}

const normaliseScan = (raw: any): NormalizedBodyspecScan | null => {
  if (!raw) return null

  const date =
    normaliseDate(raw.scan_date) ||
    normaliseDate(raw.performed_at) ||
    normaliseDate(raw.recorded_at) ||
    normaliseDate(raw.date) ||
    normaliseDate(raw.taken_at)

  if (!date) {
    return null
  }

  const weightUnit = determineWeightUnit(raw)
  const leanMass =
    numberFallback(raw.lean_mass_lbs) ??
    numberFallback(raw.lean_mass) ??
    numberFallback(raw.lean_body_mass) ??
    numberFallback(raw.stats?.lean_mass_lbs)

  const fatMass =
    numberFallback(raw.fat_mass_lbs) ??
    numberFallback(raw.fat_mass) ??
    numberFallback(raw.fat_mass_weight) ??
    numberFallback(raw.stats?.fat_mass_lbs)

  const boneMass =
    numberFallback(raw.bone_mass_lbs) ??
    numberFallback(raw.bmc_lbs) ??
    numberFallback(raw.bone_mass) ??
    numberFallback(raw.stats?.bone_mass_lbs)

  const bodyFatPercentage =
    numberFallback(raw.body_fat_percentage) ??
    numberFallback(raw.body_fat_percent) ??
    numberFallback(raw.bodyfat) ??
    numberFallback(raw.stats?.body_fat_percentage)

  const weight =
    numberFallback(raw.weight_lbs) ??
    numberFallback(raw.weight) ??
    numberFallback(raw.body_weight_lbs) ??
    numberFallback(raw.stats?.weight_lbs)

  const visceralFat =
    numberFallback(raw.visceral_fat) ??
    numberFallback(raw.visceral_fat_rating) ??
    numberFallback(raw.stats?.visceral_fat)

  const referenceId = raw.id ?? raw.measurement_id ?? raw.scan_id

  return {
    date,
    weight: weight,
    weight_unit: weightUnit,
    body_fat_percentage: bodyFatPercentage,
    lean_mass: leanMass,
    fat_mass: fatMass,
    bone_mass: boneMass,
    visceral_fat: visceralFat,
    source: 'BodySpec',
    reference_id: referenceId,
    raw,
  }
}

async function signIn(credentials: BodyspecCredentials, baseUrl: string): Promise<BodyspecAuthSession> {
  const response = await fetch(`${baseUrl}/users/sign_in`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'LogYourBody MCP/1.0',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      user: {
        email: credentials.email,
        password: credentials.password,
      },
    }),
  })

  if (!response.ok) {
    let errorDetails: unknown
    try {
      errorDetails = await response.json()
    } catch (_) {
      // ignore json parse errors
    }

    throw new BodyspecRequestError('Unable to authenticate with BodySpec', {
      status: response.status,
      details: errorDetails,
    })
  }

  const accessToken = response.headers.get('access-token')
  const client = response.headers.get('client')
  const uid = response.headers.get('uid') ?? credentials.email
  const expiry = response.headers.get('expiry') ?? undefined
  const tokenType = response.headers.get('token-type') ?? undefined

  if (!accessToken || !client || !uid) {
    throw new BodyspecRequestError('BodySpec authentication response was missing tokens', {
      status: response.status,
    })
  }

  return {
    accessToken,
    client,
    uid,
    expiry,
    tokenType,
  }
}

async function fetchMeasurements(session: BodyspecAuthSession, baseUrl: string, perPage = 100) {
  const search = new URLSearchParams({
    per_page: String(perPage),
    order: 'desc',
  })

  const response = await fetch(`${baseUrl}/dxa_scans?${search.toString()}`, {
    method: 'GET',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
      'access-token': session.accessToken,
      client: session.client,
      uid: session.uid,
      ...(session.tokenType ? { 'token-type': session.tokenType } : {}),
    },
  })

  if (!response.ok) {
    let errorDetails: unknown
    try {
      errorDetails = await response.json()
    } catch (_) {
      // ignore
    }

    throw new BodyspecRequestError('Unable to fetch BodySpec scan history', {
      status: response.status,
      details: errorDetails,
    })
  }

  const payload = await response.json()
  const scansArray = Array.isArray(payload?.data) ? payload.data : Array.isArray(payload) ? payload : []

  return scansArray
}

export interface FetchBodyspecScansOptions {
  credentials?: BodyspecCredentials
  session?: BodyspecAuthSession
  baseUrl?: string
  perPage?: number
}

export async function fetchBodyspecScans(options: FetchBodyspecScansOptions) {
  const baseUrl = options.baseUrl ?? process.env.BODYSPEC_API_BASE_URL ?? DEFAULT_BASE_URL

  if (!options.credentials && !options.session) {
    throw new BodyspecRequestError('BodySpec credentials or session are required')
  }

  const session = options.session ?? (await signIn(options.credentials as BodyspecCredentials, baseUrl))
  const rawScans = await fetchMeasurements(session, baseUrl, options.perPage)
  const rawArray: unknown[] = Array.isArray(rawScans) ? rawScans : []
  const normalized = rawArray
    .map((scan) => normaliseScan(scan))
    .filter((scan): scan is NormalizedBodyspecScan => Boolean(scan))
    .sort((a, b) => a.date.localeCompare(b.date))

  return {
    scans: normalized,
    session,
    raw: rawScans,
  }
}

export default fetchBodyspecScans
