export type AccountDeletionTarget = {
  table: string;
  column: string;
  required: boolean;
};

export type AccountDeletionResult = AccountDeletionTarget & {
  success: boolean;
  error?: string;
};

type SupabaseDeleteBuilder = {
  eq: (column: string, value: string) => PromiseLike<{ error?: unknown }>;
};

type SupabaseDeleteClient = {
  from: (table: string) => {
    delete: () => SupabaseDeleteBuilder;
  };
};

type SupabaseAuthAdminClient = {
  auth: {
    admin: {
      deleteUser: (userId: string) => Promise<{ error?: unknown }>;
    };
  };
};

type AccountDeletionLogger = {
  error: (message: string, context?: unknown) => void;
};

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
];

export const legacyAccountDeletionTargets: readonly AccountDeletionTarget[] = [
  { table: "progress_photos_old", column: "user_id", required: true },
  { table: "weight_logs_old", column: "user_id", required: true },
  { table: "daily_metrics_old", column: "user_id", required: true },
  { table: "body_metrics_old", column: "user_id", required: true },
  { table: "email_subscriptions_old", column: "user_id", required: true },
  { table: "profiles_old", column: "id", required: true },
];

export class UserDataDeletionError extends Error {
  constructor(public readonly results: readonly AccountDeletionResult[]) {
    const failedTables = results
      .filter((result) => result.required && !result.success)
      .map((result) => result.table)
      .join(", ");

    super(`Failed to delete required account data from: ${failedTables}`);
    this.name = "UserDataDeletionError";
  }
}

export async function deleteUserDatabaseRows(
  supabase: SupabaseDeleteClient,
  userId: string,
  logger: AccountDeletionLogger = console,
): Promise<AccountDeletionResult[]> {
  return deleteTargets(supabase, userId, accountDeletionTargets, logger);
}

export async function deleteLegacyUserDatabaseRows(
  supabase: SupabaseDeleteClient,
  userId: string,
  logger: AccountDeletionLogger = console,
): Promise<AccountDeletionResult[]> {
  return deleteTargets(supabase, userId, legacyAccountDeletionTargets, logger);
}

async function deleteTargets(
  supabase: SupabaseDeleteClient,
  userId: string,
  targets: readonly AccountDeletionTarget[],
  logger: AccountDeletionLogger,
): Promise<AccountDeletionResult[]> {
  if (userId.trim().length === 0) {
    throw new Error("Cannot delete account data without a user id");
  }

  const results: AccountDeletionResult[] = [];

  for (const target of targets) {
    const { error } = await supabase
      .from(target.table)
      .delete()
      .eq(target.column, userId);

    if (error) {
      const result = {
        ...target,
        success: false,
        error: describeSupabaseError(error),
      };
      results.push(result);
      logger.error("Failed to delete account data table", {
        table: target.table,
        column: target.column,
        required: target.required,
        error,
      });
      continue;
    }

    results.push({ ...target, success: true });
  }

  const hasRequiredFailure = results.some((result) =>
    result.required && !result.success
  );
  if (hasRequiredFailure) {
    throw new UserDataDeletionError(results);
  }

  return results;
}

export async function deleteProductAuthUser(
  supabase: SupabaseAuthAdminClient,
  userId: string,
): Promise<void> {
  if (userId.trim().length === 0) {
    throw new Error("Cannot delete product auth user without a user id");
  }

  const { error } = await supabase.auth.admin.deleteUser(userId);
  if (error) {
    throw new Error(
      `Failed to delete product auth user: ${describeSupabaseError(error)}`,
    );
  }
}

function describeSupabaseError(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === "object" && error !== null) {
    const record = error as Record<string, unknown>;
    const message = record.message ?? record.details ?? record.code;
    if (typeof message === "string" && message.length > 0) {
      return message;
    }
  }

  return String(error);
}

export function ownedStoragePathFromValue(
  value: string | null,
  userId: string,
): string | null {
  if (!value || !userId) return null;

  let path = value;
  if (value.startsWith("http")) {
    const patterns = [
      "/storage/v1/object/public/photos/",
      "/storage/v1/object/photos/",
    ];
    const pattern = patterns.find((candidate) => value.includes(candidate));
    if (!pattern) return null;
    path = value.substring(value.indexOf(pattern) + pattern.length);
  }

  const normalizedPath = path.replace(/^\/+/, "");
  if (
    normalizedPath.includes("..") ||
    !normalizedPath.startsWith(`${userId}/`)
  ) {
    return null;
  }
  return normalizedPath;
}

export function ownedCloudinaryPublicIdFromUrl(
  value: string | null,
  userId: string,
  ownedMetricIds: ReadonlySet<string>,
): string | null {
  if (
    !value ||
    !/^[A-Za-z0-9_-]+$/.test(userId) ||
    !value.includes("res.cloudinary.com") ||
    !value.includes("/upload/")
  ) {
    return null;
  }

  const uploadIndex = value.indexOf("/upload/");
  const segments = value.substring(uploadIndex + "/upload/".length)
    .split("/")
    .filter(Boolean);
  const folderIndex = segments.lastIndexOf("progress-photos");
  if (folderIndex === -1) return null;

  let path = segments.slice(folderIndex).join("/");
  const dotIndex = path.lastIndexOf(".");
  if (dotIndex !== -1) path = path.substring(0, dotIndex);

  const ownerPrefix = `progress-photos/${userId}/`;
  if (!path.startsWith(ownerPrefix)) return null;

  const resourceName = path.substring(ownerPrefix.length);
  if (resourceName.includes("/")) return null;
  const separatorIndex = resourceName.lastIndexOf("_");
  if (separatorIndex <= 0) return null;
  const metricId = resourceName.substring(0, separatorIndex);
  const timestamp = resourceName.substring(separatorIndex + 1);
  if (!ownedMetricIds.has(metricId) || !/^\d+$/.test(timestamp)) return null;

  return path;
}
