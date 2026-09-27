import { readFileSync } from 'node:fs';
import path from 'node:path';
import { defineEval } from 'eve/evals';

interface KnowledgeCase {
  topic: string;
  question: string;
  expected_fact_ids: string[];
}

const fixturePath = path.join(process.cwd(), 'evals/knowledge-golden/cases.json');
const fixture = JSON.parse(readFileSync(fixturePath, 'utf8')) as {
  version?: number;
  cases?: KnowledgeCase[];
};
if (fixture.version !== 1 || !Array.isArray(fixture.cases) || fixture.cases.length !== 180) {
  throw new Error('Expected 180 non-quarantined version-one knowledge eval cases');
}

export default fixture.cases.map((row) =>
  defineEval({
    description: 'Loads the topic skill and returns only its expected evidence IDs.',
    tags: ['knowledge', 'skill-routing'],
    async test(t) {
      const turn = await t.send(row.question);
      t.succeeded();
      t.loadedSkill(row.topic, { count: 1 });
      for (const id of row.expected_fact_ids) turn.messageIncludes('[' + id + ']');
    },
  }),
);
