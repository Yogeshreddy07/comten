from firebase_admin import firestore
from .store import db,get,all_rows


def refresh_project_roster(pid):
    """Reconcile privileged assignment changes and invalidate affected account caches."""
    project=get('projects',pid)
    if not project:return
    modules=[m for m in all_rows('modules',[('projectId',int(pid))]) if m.get('active',True) and not m.get('deleted')]
    members=set()
    for m in modules:
        members.update(m.get('memberIds',[]))
        if m.get('teamLeadId'):members.add(m['teamLeadId'])
    db.collection('projects').document(str(pid)).update({'memberIds':sorted(members)})
    for uid in members|set(project.get('memberIds',[])):
        if not get('employees',uid):continue
        leads=set()
        peers={uid}
        for m in all_rows('modules',[('memberIds','array_contains',uid)]):
            parent=get('projects',m['projectId'])
            if m.get('active',True) and not m.get('deleted') and parent and parent.get('active') and not parent.get('deleted'):
                peers.update(m.get('memberIds',[]))
                if m.get('teamLeadId'):leads.add(m['teamLeadId'])
        db.collection('employees').document(str(uid)).update({'teamLeadIds':sorted(leads),'peerIds':sorted(peers),'permissionVersion':firestore.Increment(1)})
