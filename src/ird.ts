export type IrdSyncStatus = 'pending' | 'synced' | 'failed' | 'not_required';

export interface IrdSyncResult {
  status: IrdSyncStatus;
  reference?: string;
  error?: string;
}

export interface IrdAdapter {
  syncTransaction(transactionId: string): Promise<IrdSyncResult>;
}

/** Prototype-only adapter. It performs no network call and makes no compliance claim. */
export class MockIrdAdapter implements IrdAdapter {
  async syncTransaction(_transactionId: string): Promise<IrdSyncResult> {
    return { status: 'not_required' };
  }
}

