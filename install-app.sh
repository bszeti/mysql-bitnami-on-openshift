oc new-project app

# Create ConfigMap with python app
oc delete cm -n app app; oc create cm -n app app --from-file=deploy-app/requirements.txt --from-file=deploy-app/mysql-insert.py

# Create Job to run app inserting rows into a MySQL database
oc delete -n app -f deploy-app/job-mysql-insert.yaml; oc create -n app -f deploy-app/job-mysql-insert.yaml
oc wait -n app --for=jsonpath='{.status.ready}'=1 job/mysql-insert
oc logs -n app -f job/mysql-insert

# oc delete -n app -f deploy-app/job-mysql-insert.yaml
