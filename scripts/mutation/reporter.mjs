// Only structured test outcomes are emitted; console output is not evidence.
export default async function* report(events) {
  for await (const event of events) {
    if (event.type === 'test:fail') {
      const error = event.data.details?.error;
      yield JSON.stringify({
        type: 'failure',
        name: event.data.name,
        code: error?.code,
        causeCode: error?.cause?.code,
        failureType: error?.failureType,
      }) + '\n';
    } else if (event.type === 'test:summary') {
      yield JSON.stringify({ type: 'summary', ...event.data }) + '\n';
    } else if (event.type === 'test:coverage') {
      yield JSON.stringify({ type: 'coverage', summary: event.data.summary }) + '\n';
    }
  }
}
