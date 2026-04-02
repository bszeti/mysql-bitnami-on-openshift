# MySQL instance name. Also update MYSQL_SERVICE in deploy-mysql/job-restore.yaml
INSTANCE=test
NAMESPACE=mysql-restore

# Create namespace 
# oc new-project $NAMESPACE

# Secret for GCP credentials
# oc apply -n $NAMESPACE -f deploy-mysql/secret-gcp-credentials.yaml

# ConfigMap with scripts used in secondary node sidecars
oc apply -n $NAMESPACE -f deploy-mysql/scripts-sidecars.yaml

# Install MySQL with bin backup sidecars
helm upgrade -i -n $NAMESPACE --wait --timeout=5m $INSTANCE oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml

# Create job to restore databases from backup
oc delete -n $NAMESPACE -f deploy-mysql/job-restore.yaml; oc create -f deploy-mysql/job-restore.yaml
oc wait -n $NAMESPACE --for=jsonpath='{.status.ready}'=1 job/restore
oc logs -n $NAMESPACE -f -c download job/restore
oc logs -n $NAMESPACE -f -c restore job/restore

# Verify restored db
oc exec -n $NAMESPACE -c mysql $INSTANCE-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"'
oc exec -n $NAMESPACE -c mysql $INSTANCE-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"SELECT count(*) FROM messages; SELECT * FROM messages ORDER BY created_at DESC LIMIT 1;"'
oc exec -n $NAMESPACE -c mysql $INSTANCE-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"
    SELECT 
        table_schema AS '\''Db'\'', 
        ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS '\''Size (GB)'\''
    FROM information_schema.TABLES 
    WHERE table_schema = DATABASE();
    "'

# Create CronJob for mysqldump backups for restored database
oc apply -n $NAMESPACE -f deploy-mysql/cronjob-backup-mysqldump.yaml
# Force run
job=$(oc create job -oname manual-backup-mysqldump-$(date +%Y%m%d%H%M%S) --from=cronjob/backup-mysqldump)
oc wait --for=jsonpath='{.status.ready}'=1 $job
oc logs -f -c mysqldump $job
oc logs -f -c upload $job

# Uninstall
# helm uninstall -n $NAMESPACE test
# oc delete -n $NAMESPACE -f deploy-mysql/cronjob-backup-mysqldump.yaml