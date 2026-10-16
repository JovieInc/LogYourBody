/** Split HTTP list/parameter values without treating quoted delimiters as separators. */
function splitHeader(value: string, delimiter: string): string[] {
  const parts: string[] = [];
  let start = 0;
  let quoted = false;
  let escaped = false;
  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (escaped) {
      escaped = false;
    } else if (quoted && character === '\\') {
      escaped = true;
    } else if (character === '"') {
      quoted = !quoted;
    } else if (!quoted && character === delimiter) {
      parts.push(value.slice(start, index).trim());
      start = index + 1;
    }
  }
  if (quoted || escaped) return [];
  return [...parts, value.slice(start).trim()];
}

function qualityFor(accept: string, subtype: 'html' | 'markdown'): number {
  let specificity = -1;
  let quality = 0;
  for (const range of splitHeader(accept, ',')) {
    const [media, ...parameters] = splitHeader(range, ';');
    const normalized = media?.toLowerCase();
    const rank =
      normalized === 'text/' + subtype
        ? 2
        : normalized === 'text/*'
          ? 1
          : normalized === '*/*'
            ? 0
            : -1;
    if (rank < 0) continue;

    let weight = 1;
    let hasWeight = false;
    let matchingParameters = 0;
    let valid = true;
    for (const parameter of parameters) {
      if (!parameter) continue;
      const separator = parameter.indexOf('=');
      if (separator < 1) {
        valid = false;
        break;
      }
      const name = parameter.slice(0, separator).trim().toLowerCase();
      const value = parameter.slice(separator + 1).trim();
      if (name === 'q') {
        if (hasWeight || !/^(?:0(?:\.\d{0,3})?|1(?:\.0{0,3})?)$/.test(value)) {
          valid = false;
          break;
        }
        hasWeight = true;
        weight = Number(value);
      } else if (
        name === 'charset' &&
        matchingParameters === 0 &&
        /^(?:utf-8|"utf-8")$/i.test(value)
      ) {
        matchingParameters += 1;
      } else {
        // Neither representation advertises profile/level/format parameters.
        valid = false;
        break;
      }
    }
    if (!valid) continue;
    const precedence = rank * 2 + matchingParameters;
    if (precedence > specificity) {
      specificity = precedence;
      quality = weight;
    } else if (precedence === specificity) {
      // Conflicting duplicate ranges must not resurrect an explicit q=0.
      quality = Math.min(quality, weight);
    }
  }
  return quality;
}

/** RFC9110: specific ranges determine quality; HTML wins ties and absence. */
export function prefersMarkdown(accept: string | null): boolean {
  if (!accept || accept.length > 8192) return false;
  const markdown = qualityFor(accept, 'markdown');
  return markdown > 0 && markdown > qualityFor(accept, 'html');
}

export function varyOnAccept(headers: Headers): void {
  const vary = headers.get('Vary');
  if (vary?.split(',').some((field) => ['*', 'accept'].includes(field.trim().toLowerCase())))
    return;
  headers.set('Vary', vary ? vary + ', Accept' : 'Accept');
}
