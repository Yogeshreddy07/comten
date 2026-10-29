"""Billing enrichment equivalence, bounded requests and authorization."""
import pytest
from fastapi import HTTPException
from app import operations


@pytest.mark.parametrize('role', ['CAPTAIN', 'PROJECT_CONTROLLER'])
def test_batch_matches_legacy_rows_and_deduplicates(monkeypatch, role):
    modules = [
        {'id': i, 'projectId': 1 if i < 5 else 2, 'teamLeadId': 7,
         'active': i != 4, 'status': 'IN_PROGRESS', 'workStage': 'BILLING',
         'billingStatus': status, 'estimatedMinutes': 60, 'completedMinutes': 30}
        for i, status in enumerate([None, 'INVOICE_RAISED', 'PART_PAYMENT_RECEIVED',
                                   'FULL_PAYMENT_RECEIVED', None, None], 1)
    ]
    records = {('projects', '1'): {'active': True},
               ('projects', '2'): {'active': False},
               ('employees', '7'): {'name': 'Leader'}}
    for mid, rid, state in [(1, 11, 'PENDING'), (2, 12, 'APPROVED'), (3, 13, None)]:
        records[('pending-approvals', f'billing-status-change-requests-{mid}')] = {'requestId': rid}
        if state:
            records[('billing-status-change-requests', str(rid))] = {'approvalStatus': state}
    monkeypatch.setattr(operations, 'get', lambda c, k: records.get((c, str(k))))
    # has_pending imports the same datastore separately; use its exact contract.
    def pending(c, k):
        lock = records.get(('pending-approvals', f'{c}-{k}'), {})
        return records.get((c, str(lock.get('requestId'))), {}).get('approvalStatus') == 'PENDING'
    monkeypatch.setattr(operations, 'has_pending', pending)
    expected = [operations.billing_row(m) for m in modules]
    calls = []
    def many(keys, fields=None):
        keys = list(keys)
        assert len(keys) == len(set(keys))
        calls.append(keys)
        return {k: records[k] for k in keys if k in records}
    monkeypatch.setattr(operations, 'get_many', many)
    def rows(collection, filters):
        assert collection == 'modules' and filters == [('workStage', 'BILLING')]
        return modules + [dict(modules[0], id=99, deleted=True)]
    monkeypatch.setattr(operations, 'all_rows', rows)
    assert operations.billing({'role': role})['data'] == expected
    assert len(calls) == 2
    assert len(calls[0]) == 9  # 2 parents + 1 leader + 6 locks
    assert len(calls[1]) == 3


def test_empty_billing_has_no_enrichment_reads(monkeypatch):
    monkeypatch.setattr(operations, 'all_rows', lambda *a: [])
    monkeypatch.setattr(operations, 'get_many', lambda keys, **kw: {} if not keys else pytest.fail('Unexpected reads'))
    assert operations.billing({'role': 'CAPTAIN'})['data'] == []


@pytest.mark.parametrize('role', ['EMPLOYEE', 'TEAM_LEADER'])
def test_billing_denied_before_queries(monkeypatch, role):
    monkeypatch.setattr(operations, 'all_rows', lambda *a: pytest.fail('Unauthorized query'))
    with pytest.raises(HTTPException) as exc:
        operations.billing({'role': role})
    assert exc.value.status_code == 403
