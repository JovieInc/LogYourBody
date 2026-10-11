const MAX_SPOKEN_WORDS = 12;
const MAX_SUBSTANTIVE_SENTENCES = 2;

function wordCount(text: string): number {
  return text.match(/[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*/gu)?.length ?? 0;
}

function substantiveSentenceCount(text: string): number {
  return (text.match(/[^.!?]+[.!?]?/g) ?? []).filter((sentence) => wordCount(sentence) > 3).length;
}

function asksQuestion(prompt: string): boolean {
  return (
    prompt.includes('?') ||
    /^\s*(?:what|why|when|where|who|whom|which|whose|how|can|could|would|should|is|are|was|were|do|does|did|will|may|might|have|has|had)\b/i.test(
      prompt,
    )
  );
}

export function evaluateSpokenReply(prompt: string, reply: string) {
  const words = wordCount(reply);
  const sentences = substantiveSentenceCount(reply);
  const questionException = asksQuestion(prompt);
  const violations = questionException
    ? []
    : [
        ...(words > MAX_SPOKEN_WORDS ? ['word_limit'] : []),
        ...(sentences > MAX_SUBSTANTIVE_SENTENCES ? ['sentence_limit'] : []),
      ];

  return { passed: violations.length === 0, words, sentences, questionException, violations };
}
