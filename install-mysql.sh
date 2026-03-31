# Secret for GCP credentials
# oc apply -f deploy-mysql/secret-gcp-credentials.yaml

# ConfigMap with scripts used in secondary node sidecars
oc apply -f deploy-mysql/scripts-sidecars.yaml

# Install MySQL with bin backup sidecars
helm upgrade -i test --wait --timeout=5m oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-sidecar.yaml

# Create CronJob for mysqldump backups
oc apply -f deploy-mysql/cronjob-backup-mysqldump.yaml
# Force run
jobname=$(oc create job manual-backup-mysqldump-$(date +%Y%m%d%H%M%S) --from=cronjob/backup-mysqldump)
oc wait --for=jsonpath='{.status.ready}'=1 $jobname
oc logs -f -c mysqldump $jobname
oc logs -f -c upload $jobname

# # Uninstall
# helm uninstall -n mysql test
# oc delete -f deploy-mysql/cronjob-backup.yaml