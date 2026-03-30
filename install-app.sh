oc new-project app

oc create cm -n app app --from-file=deploy-app/requirements.txt --from-file=deploy-app/mysql-insert.py

oc delete -n app -f deploy-app/job-mysql-insert.yaml; oc create -n app -f deploy-app/job-mysql-insert.yaml
oc wait -n app --for=jsonpath='{.status.ready}'=1 job/mysql-insert
oc logs -n app -f job/mysql-insert

# oc delete -f deploy-app/job-mysql-insert.yaml
