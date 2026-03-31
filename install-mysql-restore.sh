# Secret for GCP credentials
# oc apply -f deploy-mysql/secret-gcp-credentials.yaml

# ConfigMap with scripts used in secondary node sidecars
oc apply -f deploy-mysql/scripts-sidecars.yaml

# Install MySQL with bin backup sidecars
helm upgrade -i --wait --timeout=5m restore oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml

# Create job to restore databases from backup
oc delete -f deploy-mysql/job-restore.yaml; oc create -f deploy-mysql/job-restore.yaml
oc wait --for=jsonpath='{.status.ready}'=1 job/restore
oc logs -f -c download job/restore
oc logs -f -c restore job/restore

# Verify restored db
oc exec -c mysql restore-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"'
oc exec -c mysql restore-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"SELECT count(*) FROM messages; SELECT * FROM messages ORDER BY created_at DESC LIMIT 1;"'
oc exec -c mysql restore-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"
    SELECT 
        table_schema AS '\''Db'\'', 
        ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS '\''Size (GB)'\''
    FROM information_schema.TABLES 
    WHERE table_schema = DATABASE();
    "'

# Create CronJob for mysqldump backups
oc apply -f deploy-mysql/cronjob-backup.yaml



# Uninstall
# helm uninstall -n mysql restore
# oc delete -f deploy-mysql/cronjob-backup.yaml