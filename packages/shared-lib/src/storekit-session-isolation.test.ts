import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';

it('StoreKit cleanup deletes only captured transactions before polling full history', () => {
  const source = readFileSync(
    new URL(
      '../../../apps/ios/LogYourBodyTests/StoreKitPurchaseRestoreTests.swift',
      import.meta.url,
    ),
    'utf8',
  );

  // A delayed global clear can erase a later purchase. Deleting captured IDs cannot.
  expect(source).not.toMatch(/\.clearTransactions\s*\(/);
  expect(source).toContain('for transaction in session.allTransactions() {');
  expect(source).toContain('try session.deleteTransaction(identifier: transaction.identifier)');
  // No entitlement can also mean expired/refunded history: wait for both API views.
  expect(source).toContain('for await _ in StoreKit.Transaction.all');
  expect(source).toContain('session.allTransactions().isEmpty, !(await hasStoreKitHistory())');
  const poll = source.match(/for _ in 0\.\.<50 \{([\s\S]*?)\n {4}\}/)?.[1];
  expect(poll).toBeDefined();
  expect(poll).not.toMatch(
    /session\.(?:resetToDefaultState|deleteTransaction|clearTransactions)\s*\(/,
  );
  expect(poll).toContain('try await Task.sleep');
  expect(source).toContain('throw SetUpError.storeKitStateDidNotSettle');
});
