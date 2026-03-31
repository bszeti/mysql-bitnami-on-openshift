oc delete -n mysql -f load-data/job-load-data.yaml; oc create -n mysql -f load-data/job-load-data.yaml
oc wait -n mysql --for=jsonpath='{.status.ready}'=1 job/load-data
oc logs -n mysql -f job/load-data
