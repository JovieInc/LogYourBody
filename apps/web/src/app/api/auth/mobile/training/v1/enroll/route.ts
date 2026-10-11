import { trainingHandlers } from '../dependencies';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';
export const POST = trainingHandlers.enroll;
export const DELETE = trainingHandlers.revoke;
