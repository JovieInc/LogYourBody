export type AccountDeletionTarget = {
    table: string
    column: string
    required: boolean
}

export type AccountDeletionResult = AccountDeletionTarget & {
    success: boolean
    error?: string
}

type SupabaseDeleteBuilder = {
    eq: (column: string, value: string) => Promise<{ error?: unknown }>
}

type SupabaseDeleteClient = {
    from: (table: string) => {
        delete: () => SupabaseDeleteBuilder
    }
}

type SupabaseAuthAdminClient = {
    auth: {
        admin: {
            deleteUser: (userId: string) => Promise<{ error?: unknown }>
        }
    }
}

type AccountDeletionLogger = {
    error: (message: string, context?: unknown) => void
}

export const accountDeletionTargets: readonly AccountDeletionTarget[] = [
    // Export rows are temporary, but they can contain a full health-data snapshot.
    { table: "data_exports", column: "user_id", required: true },
    { table: "progress_photos", column: "user_id", required: true },
    { table: "dexa_results", column: "user_id", required: true },
    { table: "glp1_dose_logs", column: "user_id", required: true },
    { table: "glp1_medications", column: "user_id", required: true },
    { table: "daily_metrics", column: "user_id", required: true },
    { table: "body_metrics", column: "user_id", required: true },
    { table: "email_subscriptions", column: "user_id", required: true },
    { table: "profiles", column: "id", required: true },
]

export class UserDataDeletionError extends Error {
    constructor(public readonly results: readonly AccountDeletionResult[]) {
        const failedTables = results
            .filter((result) => result.required && !result.success)
            .map((result) => result.table)
            .join(", ")

        super(`Failed to delete required account data from: ${failedTables}`)
        this.name = "UserDataDeletionError"
    }
}

export async function deleteUserDatabaseRows(
    supabase: SupabaseDeleteClient,
    userId: string,
    logger: AccountDeletionLogger = console,
): Promise<AccountDeletionResult[]> {
    if (userId.trim().length === 0) {
        throw new Error("Cannot delete account data without a user id")
    }

    const results: AccountDeletionResult[] = []

    for (const target of accountDeletionTargets) {
        const { error } = await supabase
            .from(target.table)
            .delete()
            .eq(target.column, userId)

        if (error) {
            const result = {
                ...target,
                success: false,
                error: describeSupabaseError(error),
            }
            results.push(result)
            logger.error("Failed to delete account data table", {
                table: target.table,
                column: target.column,
                required: target.required,
                error,
            })
            continue
        }

        results.push({ ...target, success: true })
    }

    const hasRequiredFailure = results.some((result) => result.required && !result.success)
    if (hasRequiredFailure) {
        throw new UserDataDeletionError(results)
    }

    return results
}

export async function deleteProductAuthUser(
    supabase: SupabaseAuthAdminClient,
    userId: string,
): Promise<void> {
    if (userId.trim().length === 0) {
        throw new Error("Cannot delete product auth user without a user id")
    }

    const { error } = await supabase.auth.admin.deleteUser(userId)
    if (error) {
        throw new Error(`Failed to delete product auth user: ${describeSupabaseError(error)}`)
    }
}

function describeSupabaseError(error: unknown): string {
    if (error instanceof Error) {
        return error.message
    }

    if (typeof error === "object" && error !== null) {
        const record = error as Record<string, unknown>
        const message = record.message ?? record.details ?? record.code
        if (typeof message === "string" && message.length > 0) {
            return message
        }
    }

    return String(error)
}
