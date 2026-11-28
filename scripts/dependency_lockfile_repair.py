"""Identify the pinned pnpm diagnostics that allow explicit lockfile repair."""


def dependency_lockfile_refresh_allowed(output):
    errors = [line.split(maxsplit=1) for line in output.splitlines() if line.strip().startswith("ERR_PNPM_")]
    if len(errors) != 1:
        return False
    code, *message = errors[0]
    return code == "ERR_PNPM_OUTDATED_LOCKFILE" or (
        code == "ERR_PNPM_LOCKFILE_CONFIG_MISMATCH" and message == [
            'Cannot proceed with the frozen installation. The current "overrides" '
            "configuration doesn't match the value found in the lockfile"
        ]
    )
