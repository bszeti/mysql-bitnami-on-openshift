# Secret for GCP credentials
# oc apply -f deploy-mysql/secret-gcp-credentials.yaml

# ConfigMap with scripts used in secondary node sidecars
oc apply -f deploy-mysql/scripts-sidecars.yaml

# Install MySQL with bin backup sidecars
helm upgrade -i restore oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml

# Create job to restore databases from backup
# oc delete -f deploy-mysql/job-restore.yaml
oc apply -f deploy-mysql/job-restore.yaml
oc wait --for=jsonpath='{.status.ready}'=1 job/restore
oc logs -f -c download job/restore
oc logs -f -c restore job/restore

# Create CronJob for mysqldump backups
oc apply -f deploy-mysql/cronjob-backup.yaml



# Uninstall
# helm uninstall -n mysql restore
# oc delete -f deploy-mysql/cronjob-backup.yaml