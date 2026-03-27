# Secret for GCP credentials
# oc apply -f deploy-mysql/secret-gcp-credentials.yaml

# ConfigMap with scripts used in secondary node sidecars
oc apply -f deploy-mysql/scripts-sidecars.yaml

# Install MySQL with bin backup sidecars
helm upgrade -i restore oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml

# Create job to restore databases from backup
# TODO

# Create CronJob for mysqldump backups
oc apply -f deploy-mysql/cronjob-backup.yaml



# Uninstall
# helm uninstall -n mysql restore
# oc delete -f deploy-mysql/cronjob-backup.yaml