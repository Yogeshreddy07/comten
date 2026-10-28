from app import operations


def test_batched_billing_matches_individual_rows_including_stale_locks(monkeypatch):
    modules = [
        {'id':1,'projectId':10,'teamLeadId':20,'active':True,'billingStatus':'INVOICE_RAISED'},
        {'id':2,'projectId':11,'teamLeadId':20,'billingStatus':'FULL_PAYMENT_RECEIVED'},
        {'id':3,'projectId':12,'teamLeadId':99},
        {'id':4,'projectId':10,'active':False},
        {'id':5,'projectId':10,'teamLeadId':20},
    ]
    docs = {
        ('projects','10'):{'active':True},
        ('projects','11'):{'active':True,'deleted':True},
        ('employees','20'):{'name':'Synthetic'},
        ('pending-approvals','billing-status-change-requests-1'):{'requestId':600},
        ('pending-approvals','billing-status-change-requests-2'):{'requestId':601},
        ('pending-approvals','billing-status-change-requests-3'):{'requestId':602},
        ('pending-approvals','billing-status-change-requests-4'):{'requestId':None},
        ('billing-status-change-requests','600'):{'approvalStatus':'PENDING'},
        ('billing-status-change-requests','601'):{'approvalStatus':'APPROVED'},
    }
    monkeypatch.setattr(operations,'get',lambda collection,key:docs.get((collection,str(key))))
    monkeypatch.setattr(operations,'has_pending',lambda collection,mid:mid==1)
    expected=[operations.billing_row(m) for m in modules]
    calls=[]
    def many(keys, fields=None):
        calls.append((list(keys),fields))
        return {(collection,str(key)):docs[(collection,str(key))] for collection,key in keys if (collection,str(key)) in docs}
    monkeypatch.setattr(operations,'get_many',many)
    assert operations.billing_rows(modules)==expected
    assert len(calls)==2
    assert len(set(calls[1][0]))==3
    assert expected[0]['reversionPending'] is True
    assert expected[1]['editable'] is False
    assert expected[2]['teamLeadName'] is None
    assert expected[3]['editable'] is False
    assert all(not row['reversionPending'] for row in expected[1:])


def test_billing_query_filters_before_enrichment_and_preserves_manager_check(monkeypatch):
    from fastapi import HTTPException
    import pytest
    calls=[]
    def all_rows(collection,filters=()):
        calls.append((collection,filters))
        return [{'id':1,'deleted':True}, {'id':2}]
    monkeypatch.setattr(operations,'all_rows',all_rows)
    monkeypatch.setattr(operations,'billing_rows',lambda modules:modules)
    assert operations.billing(user={'role':'CAPTAIN'})['data']==[{'id':2}]
    assert calls==[('modules',[('workStage','BILLING')])]
    with pytest.raises(HTTPException) as error:
        operations.billing(user={'role':'EMPLOYEE'})
    assert error.value.status_code==403
