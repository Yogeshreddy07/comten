from firebase_admin import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from .store import db, transact


def refresh_project_roster(pid):
    """Reconcile the affected assignment graph using shared reads and one commit.

    Transaction retries prevent concurrent reconciliations from publishing an
    older permission roster. All reads precede writes.
    """
    ref = db.collection('projects').document(str(pid))

    @firestore.transactional
    def reconcile(tx):
        snapshot = ref.get(transaction=tx)
        if not snapshot.exists:
            return
        project = snapshot.to_dict()
        modules = [s.to_dict() for s in db.collection('modules').where(
            filter=FieldFilter('projectId', '==', int(pid))).stream(transaction=tx)]
        members = set()
        for module in modules:
            if module.get('active', True) and not module.get('deleted'):
                members.update(module.get('memberIds', []))
                if module.get('teamLeadId'):
                    members.add(module['teamLeadId'])
        affected = sorted(members | set(project.get('memberIds', [])))
        related = {}
        # Share module queries across employees, in Firestore's groups of 30.
        for offset in range(0, len(affected), 30):
            for snap in db.collection('modules').where(filter=FieldFilter(
                    'memberIds', 'array_contains_any', affected[offset:offset + 30])).stream(transaction=tx):
                related[snap.id] = snap.to_dict()
        parent_ids = {m['projectId'] for m in related.values()} - {int(pid)}
        parents = {int(pid): project}
        if parent_ids:
            for snap in db.get_all([db.collection('projects').document(str(key))
                                    for key in parent_ids], transaction=tx):
                if snap.exists:
                    parents[int(snap.id)] = snap.to_dict()
        employees = list(db.get_all([db.collection('employees').document(str(uid))
                                     for uid in affected], field_paths=['id'], transaction=tx)) if affected else []
        leads = {uid: set() for uid in affected}
        peers = {uid: {uid} for uid in affected}
        affected_set = set(affected)
        for module in related.values():
            parent = parents.get(module['projectId'])
            if not (module.get('active', True) and not module.get('deleted')
                    and parent and parent.get('active') and not parent.get('deleted')):
                continue
            module_members = set(module.get('memberIds', []))
            for uid in module_members & affected_set:
                peers[uid].update(module_members)
                if module.get('teamLeadId'):
                    leads[uid].add(module['teamLeadId'])
        tx.update(ref, {'memberIds': sorted(members)})
        for employee in employees:
            if employee.exists:
                uid = int(employee.id)
                tx.update(employee.reference, {
                    'teamLeadIds': sorted(leads[uid]), 'peerIds': sorted(peers[uid]),
                    'permissionVersion': firestore.Increment(1)})

    return transact(reconcile)
