import { beforeEach, describe, expect, it, vi } from 'vitest';

const state = vi.hoisted(() => ({
  db: {
    collection: vi.fn(),
    Timestamp: vi.fn(() => 'server-timestamp'),
  },
}));

vi.mock('../src/database/index.js', () => ({ db: state.db, admin: {} }));
vi.mock('../src/utils/helpers.js', () => ({
  generateFormId: vi.fn(async () => 'CTS-FORM-1'),
}));

const { auditService } = await import('../src/services/auditService.js');
const { contractService } = await import('../src/services/contractService.js');
const { ctsFormService } = await import('../src/services/ctsFormService.js');

describe('contract ID propagation to forms', () => {
  beforeEach(() => vi.clearAllMocks());

  it('includes the Firestore contract ID in entity contract lists', async () => {
    const query = {
      where: vi.fn(),
      limit: vi.fn(),
      get: vi.fn(async () => ({
        empty: false,
        forEach: callback => callback({
          id: 'contract-doc-id',
          data: () => ({ contractNumber: 'C-100', workCategories: ['CTS'] }),
        }),
      })),
    };
    query.where.mockReturnValue(query);
    query.limit.mockReturnValue(query);
    state.db.collection.mockReturnValue(query);

    const result = await contractService.getContractsByEntity('entity-1', {});

    expect(result.contracts[0].uid).toBe('contract-doc-id');
  });

  it('uses the signed-in contractor contract when CTS request contractId is empty', async () => {
    const savedForm = vi.fn();
    state.db.collection.mockImplementation(name => ({
      doc: id => {
        if (name === 'contracts' && id === 'contract-from-user') {
          return { get: async () => ({ exists: true, data: () => ({ status: 'Active', workCategories: ['CTS'] }) }) };
        }
        if (name === 'trains' && id === 'train-1') {
          return { get: async () => ({ exists: true, data: () => ({ TrainApplicableFor: ['CTS'], trainNo: '100', trainName: 'Express' }) }) };
        }
        if (name === 'users') {
          return { get: async () => ({ exists: false, data: () => ({}) }) };
        }
        if (name === 'ctsForms') return { set: savedForm };
        throw new Error(`Unexpected collection/document ${name}/${id}`);
      },
    }));

    const result = await ctsFormService.submitCtsForm({
      uid: 'contractor-1',
      contractId: 'contract-from-user',
      division: 'Division 1',
      entityId: 'entity-1',
    }, {
      trainId: 'train-1',
      formDateTime: '2026-10-22T12:00:00.000Z',
      submittedTo: {},
      signature: {},
    });

    expect(result.uid).toBe('CTS-FORM-1');
    expect(savedForm).toHaveBeenCalledWith(expect.objectContaining({
      contractId: 'contract-from-user',
      trainId: 'train-1',
    }));
  });
});

describe('filtered audit logs', () => {
  beforeEach(() => vi.clearAllMocks());

  it('filters escalation actions without a Firestore composite order index', async () => {
    const query = {
      where: vi.fn(),
      orderBy: vi.fn(),
      limit: vi.fn(),
      get: vi.fn(async () => ({
        forEach: callback => [
          { id: 'older', data: () => ({ action: 'ESCALATION_CREATED', timestamp: '2026-10-20T00:00:00.000Z' }) },
          { id: 'newer', data: () => ({ action: 'ESCALATION_CREATED', timestamp: '2026-10-22T00:00:00.000Z' }) },
        ].forEach(callback),
      })),
    };
    query.where.mockReturnValue(query);
    query.orderBy.mockReturnValue(query);
    query.limit.mockReturnValue(query);
    state.db.collection.mockReturnValue(query);

    const result = await auditService.getAuditLogs({ action: 'ESCALATION_CREATED', limit: 100 });

    expect(query.where).toHaveBeenCalledWith('action', '==', 'ESCALATION_CREATED');
    expect(query.orderBy).not.toHaveBeenCalled();
    expect(result.logs.map(log => log.timestamp)).toEqual([
      '2026-10-22T00:00:00.000Z',
      '2026-10-20T00:00:00.000Z',
    ]);
  });
});
