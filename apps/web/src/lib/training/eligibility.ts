export function profileConfirmsAdult(dateOfBirth: unknown, today: Date): boolean {
  if (typeof dateOfBirth !== 'string') return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateOfBirth.slice(0, 10));
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  )
    return false;
  let age = today.getUTCFullYear() - year;
  const birthdayPassed =
    today.getUTCMonth() + 1 > month ||
    (today.getUTCMonth() + 1 === month && today.getUTCDate() >= day);
  if (!birthdayPassed) age -= 1;
  return age >= 18;
}
