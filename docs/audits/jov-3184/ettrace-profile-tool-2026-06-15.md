# JOV-3184 ETTrace Profile Tool - 2026-06-15

## Summary

This pass adds a repo-owned ETTrace profiling entrypoint for the remaining
JOV-3184 risk: getting a real symbolicated simulator trace after `xctrace`
simulator recording produced unusable partial `.trace` bundles.

The tool does not add ETTrace to the production app target. It builds or reuses
a simulator ETTrace.xcframework inside a temporary run directory, links it with
temporary xcodebuild flags, embeds ETTrace.framework into the debug simulator
app bundle, installs that app on the simulator, and writes exact manual capture
instructions.

## Command

```bash
pnpm ios:ettrace-profile
```

For a launch-only connectivity smoke:

```bash
ETTRACE_CAPTURE=launch CAPTURE_SECONDS=45 pnpm ios:ettrace-profile
```

Manual mode is the recommended path for the actual timeline trace because the
agent can start ETTrace, drive the installed app through XcodeBuildMCP, stop
ETTrace, then preserve the fresh `output_*.json` files.

## Intended Timeline Flow

1. Launch the installed ETTrace-instrumented app with the timeline and performance-trace fixtures.
2. Wait for the timeline hero to settle.
3. Switch Avatar -> Photo.
4. Open Stats.
5. Return to Timeline.
6. Preserve the processed flamegraph JSON written in the run directory.

## Boundaries

- Simulator/debug profiling only.
- No committed ETTrace binary.
- No permanent production target dependency.
- The existing CI performance budget remains the merge gate; ETTrace captures
  are diagnostic evidence used to tighten future frame and hitch budgets.
