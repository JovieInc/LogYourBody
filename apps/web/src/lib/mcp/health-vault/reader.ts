import type { ProductBodyMetric } from '@/lib/ports/body-metrics';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { vaultConnectOrigins } from './constants';
import { snapshotFromSources } from './snapshot';
import type { HealthVaultReader } from './types';

export function createProductVaultReader(input: {
  records: Pick<NativeProductRecordsPort, 'listAll'>;
  bodyMetrics: { listAll(subject: string): Promise<ProductBodyMetric[]> };
  apiOrigin: string;
}): HealthVaultReader {
  return {
    async read(subject) {
      const [records, bodyMetrics] = await Promise.all([
        input.records.listAll(subject),
        input.bodyMetrics.listAll(subject),
      ]);
      return snapshotFromSources({
        dexaRecords: records.dexa_results,
        photoRecords: records.progress_photos,
        bodyMetrics,
        allowedOrigins: vaultConnectOrigins(input.apiOrigin),
      });
    },
  };
}
