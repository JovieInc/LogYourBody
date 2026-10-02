import { readFileSync } from 'node:fs';
import path from 'node:path';
import { mockModel } from 'eve/evals';

interface KnowledgeCase {
  topic: string;
  question: string;
  expected_fact_ids: string[];
}

function loadCases(): KnowledgeCase[] {
  const file = path.join(process.cwd(), 'evals/knowledge-golden/cases.json');
  const value = JSON.parse(readFileSync(file, 'utf8')) as { version?: number; cases?: unknown };
  if (value.version !== 1 || !Array.isArray(value.cases)) {
    throw new Error('Knowledge eval fixtures have an unsupported shape');
  }
  const cases = value.cases as KnowledgeCase[];
  if (cases.some((row) => !row.topic || !row.question || !row.expected_fact_ids?.length)) {
    throw new Error('Knowledge eval fixture contains an incomplete case');
  }
  if (new Set(cases.map((row) => row.question)).size !== cases.length) {
    throw new Error('Knowledge eval fixture questions must be unique');
  }
  return cases;
}

export function knowledgeEvalFixtureModel() {
  const cases = new Map(loadCases().map((row) => [row.question, row]));
  const loadRequested = new Set<string>();
  return mockModel(({ lastUserMessage, toolResults }) => {
    const row = cases.get(lastUserMessage);
    if (!row) return 'No matching knowledge eval case.';

    if (!loadRequested.has(lastUserMessage)) {
      loadRequested.add(lastUserMessage);
      return { toolCalls: [{ name: 'load_skill', input: { skill: row.topic } }] };
    }

    const citations = row.expected_fact_ids.map((id) => '[' + id + ']');
    const loadedContent = JSON.stringify(toolResults);
    if (citations.every((citation) => loadedContent.includes(citation))) {
      return 'Engine evidence ' + citations.join(' ');
    }
    return 'Authorized evidence is unavailable in the loaded skill.';
  });
}
