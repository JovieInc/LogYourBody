import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createRequire, registerHooks } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// Eve 0.27.13 can record a tool result before its request, leaving input {}.
// Repair that recorder only for evals; keep the actual loadedSkill gate unchanged.
// Remove this compatibility patch when upgrading to a verified upstream fix.
const require = createRequire(import.meta.url);
const manifestPath = require.resolve('eve/package.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
if (manifest.version !== '0.27.13') {
  throw new Error('LYB-71 recorder repair requires review for this Eve version');
}

const recorderUrl = pathToFileURL(
  path.join(path.dirname(manifestPath), 'dist/src/evals/runner/derive-run-facts.js'),
).href;
const expectedSha = '4dd1aae3284fbdbba9d8903eeaea5eba51b3235e9b0ce121f0721759c283f4ed';

function replaceOnce(source, before, after) {
  if (source.split(before).length !== 2) {
    throw new Error('LYB-71 recorder repair no longer matches the reviewed source');
  }
  return source.replace(before, after);
}

let applied = false;
registerHooks({
  load(url, context, nextLoad) {
    const loaded = nextLoad(url, context);
    if (url !== recorderUrl) return loaded;
    if (applied || loaded.source == null) {
      throw new Error('LYB-71 recorder repair must apply exactly once');
    }
    const source = Buffer.from(loaded.source).toString('utf8');
    if (createHash('sha256').update(source).digest('hex') !== expectedSha) {
      throw new Error('LYB-71 recorder repair requires review for changed Eve source');
    }
    let repaired = replaceOnce(
      source,
      'r=[],i=new Map,a=[]',
      'r=[],i=new Map,requestInputs=new Set,a=[]',
    );
    repaired = replaceOnce(
      repaired,
      '},ensureSubagentCall=',
      '},hydrateToolCall=(e,t,a)=>{let call=ensureToolCall(e,t,a);if(!requestInputs.has(e)){call.input=a;requestInputs.add(e)}return call},ensureSubagentCall=',
    );
    repaired = replaceOnce(
      repaired,
      'ensureToolCall(e.callId,e.toolName,e.input)',
      'hydrateToolCall(e.callId,e.toolName,e.input)',
    );
    repaired = replaceOnce(
      repaired,
      'ensureToolCall(e.action.callId,e.action.toolName,e.action.input)',
      'hydrateToolCall(e.action.callId,e.action.toolName,e.action.input)',
    );
    applied = true;
    return { ...loaded, source: repaired };
  },
});

// Verify activation before the CLI starts; later imports use this same module.
await import(recorderUrl);
if (!applied) throw new Error('LYB-71 recorder repair was not activated');
