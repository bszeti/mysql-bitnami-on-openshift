## Deploy MySql with Bitnami Helm chart

Helm chart source: https://github.com/bitnami/charts/tree/main/bitnami/mysql
Container image source: https://github.com/bitnami/containers/tree/main/bitnami/mysql

### Build image
```
cd containers/bitnami/mysql/9.6/debian-12
# For Podman had to remove line "--mount=type=secret,id=downloads_url,env=SECRET_DOWNLOADS_URL", see https://github.com/containers/buildah/pull/6285
podman build --arch amd64 --format docker -t quay.io/bszeti/mysql:9.6 .
```

### Deploy Helm chart:
With sidecars copying mysql bin files to GCP Object Storage. Important env vars for sidecars:
- **BUCKET_PATH**: Target URL of directory in bucket. (`gs://my-bucket-n9dps/mysql-test`) 
- **GCP_PROJECT_ID**: GCP project of the bucket.
- **MYSQL_BIN_FLUSH_PERIOD**: Period in seconds to flush logs and upload a new bin file
```
oc apply -f deploy-mysql/scripts-sidecars.yaml
helm upgrade -i -n mysql test oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-sidecar.yaml
oc logs -f test-mysql-secondary-0 -c backup-mysql-bin
```

Make sure to add a GCP service account key in Secret `gcp-credentials` first: `oc apply -f deploy-mysql/secret-gcp-credentials.yaml`

Check if secondary looks good:
```
oc rsh -c mysql --shell='/bin/bash' test-mysql-secondary-0
mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"
mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) <<<"SHOW DATABASES;"
mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"SELECT COUNT(*) from messages;"
```

### Backup CronJob
Periodically runs mysqldump and uploads file to GCP Object Storage
```
oc apply -f deploy-mysql/cronjob-backup-mysqldump.yaml
# Force a run if don't want to wait for schedule
oc create job manual-backup-mysqldump-$(date +%Y%m%d%H%M%S) --from=cronjob/backup-mysqldump
```

## Restore from backup
Deploy an empty MySQL instance (with the backup sidecars). This will have a new server UUID.
```
helm upgrade -i restore oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml
```

Create a job that loads a MySQL dump and related bin files. Set env vars in Job:
- **MYSQL_SERVICE**: Service name for MySQL instance. (`restore-mysql-primary.mysql.svc`)
- **MYSQL_DUMP_BUCKET_URL**: MySQL dump file in a bucket. (`gs://my-bucket-n9dps/mysql-test/b73ee744-2a27-11f1-9dc0-0a580a830093/mysql-dump/mysqldump-20260328181000.sql.gz`)
- **GCP_PROJECT_ID**: GCP project of the bucket.
- **SOURCE_LOG_STOP_DATETIME**: Point in time recovery limit, operations in bin files after this moment are skipped. (`2026-03-28 19:00:00`)
```
oc apply -f deploy-mysql/job-restore.yaml
```