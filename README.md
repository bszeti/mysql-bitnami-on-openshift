# Deploy MySql with Bitnami Helm chart

Helm chart source: https://github.com/bitnami/charts/tree/main/bitnami/mysql

Container image source: https://github.com/bitnami/containers/tree/main/bitnami/mysql

**_Note:_** In this example we use the Bitnami MySQL Helm chart, but similar solution works with Chainguard MySQL Helm chart too.

## Build image
As Bitnami doesn't provide public built images for this demo you should build your own image first with Docker or Podman:
```
cd containers/bitnami/mysql/9.6/debian-12
# For Podman had to remove line "--mount=type=secret,id=downloads_url,env=SECRET_DOWNLOADS_URL" from Containerimage, see https://github.com/containers/buildah/pull/6285
podman build --arch amd64 --format docker -t quay.io/bszeti/mysql:9.6 .
```

## Deploy Helm chart without backup
See `deploy-mysql/values-basic-cluster.yaml` for a primary-secondary (read only replica) deployment.
A few changes were required to make it work with MySQL v9.6:
- The line `character-set-server=UTF` in the default `values.yaml` causes an error, must use `UTF8MB4` or skip that line in `configuration`.
- The `initdbScripts` doesn't work with `.sql` files, must use a `.sh` script for custom init scripts


## Deploy with backup

The backup solution uses only the secondary node to make sure it's not affecting the primary node. It has two main components:
- A _CronJob_ taking `mysqldump` full dumps periodically (e.g. daily)
- Sidecars copying binary log files from the `data` directory periodically (e.g. hourly)

For a "Point In Time Recovery" you need both a full dump and binary logs afterwards. The backup files are stored `gzip` compressed.

See `install-mysql.sh` script to deploy.


### Backup CronJob form mysql dump
Periodically runs `mysqldump` and uploads file to GCP Object Storage. Important env vars:
- **MYSQL_SERVICE**: Service endpoint for secondary MySQL Pod
- **BUCKET_PATH**: Target URL of directory in bucket. (`gs://my-bucket-n9dps/mysql-test`) 
- **GCP_PROJECT_ID**: GCP project of the bucket.

```
oc apply -f deploy-mysql/cronjob-backup-mysqldump.yaml
# Force a run if don't want to wait for schedule
oc create job manual-backup-mysqldump-$(date +%Y%m%d%H%M%S) --from=cronjob/backup-mysqldump
```
Make sure to add a GCP service account key in Secret `gcp-credentials` first: `oc apply -f deploy-mysql/secret-gcp-credentials.yaml`

The Job uses two containers: one with MySQL CLI tools and one with Google Cloud CLI tools. Note:
- Backup non-system databases only. Backing up `mysql` database caused issue during restore.
- Upload dump file under bucket path in a `[server's UUID]/mysql-dump` directory. 



### Sidecars to backup mysql binary logs
The sidecars copy mysql binary log files to GCP Object Storage. Important env vars:
- **BUCKET_PATH**: Target URL of directory in bucket. (`gs://my-bucket-n9dps/mysql-test`) 
- **GCP_PROJECT_ID**: GCP project of the bucket.
- **MYSQL_BIN_FLUSH_PERIOD**: Period in seconds to flush logs and upload a new bin file (e.g 3600)
```
oc apply -f deploy-mysql/scripts-sidecars.yaml
helm upgrade -i -n mysql test oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-backup.yaml
oc logs -f test-mysql-secondary-0 -c backup-mysql-bin
```

Check if secondary looks good:
```
oc rsh -c mysql --shell='/bin/bash' test-mysql-secondary-0
    mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"
    mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) <<<"SHOW DATABASES;"
    mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) db1 <<<"SELECT COUNT(*) from messages;"
```

We have two sidecars: one with MySQL CLI tools and one with Google Cloud CLI tools. Note:
- Enforce log rotation periodically to make sure to have a closed bin log for upload.
- Compare existing bin logs in bucket and in `data` directory. Ignore the last - open - log file.
- Upload bin log files under bucket path in a `[server's UUID]/mysql-bin` directory. 

See `scripts-sidecars.yaml` for scripts.

## Restore from backup
A restore must be done in a brand new MySQL deployment. It has two main steps:
- Load a `mysql-dump` file, that also contains a comment about the last binary log file and position
- Load additional `mysql-bin` files starting from the given file and position

The solution also supports Point In Time Recoery up to a given timestamp.

Deploy an empty MySQL instance (with the backup sidecars) without any init scripts. This will have a new server UUID.
```
helm upgrade -i restore oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-restore.yaml
```

Create a job that loads a MySQL dump and related bin files. Set env vars in Job:
- **MYSQL_SERVICE**: Service endpoint for MySQL instance. (`restore-mysql-primary.mysql.svc`)
- **MYSQL_DUMP_BUCKET_URL**: MySQL dump file in a bucket. (`gs://my-bucket-n9dps/mysql-test/b73ee744-2a27-11f1-9dc0-0a580a830093/mysql-dump/mysqldump-20260328181000.sql.gz`)
- **GCP_PROJECT_ID**: GCP project of the bucket.
- **SOURCE_LOG_STOP_DATETIME**: (Optional) Point In Time Recovery UTC timestamp. Operations in bin files after this moment are skipped. ( `2026-03-28 19:00:00`)
```
oc apply -f deploy-mysql/job-restore.yaml
# Follow logs
oc logs -f -c download job/restore
oc logs -f -c restore job/restore
```

The Job uses two containers: one with MySQL CLI tools and one with Google Cloud CLI tools. Note:
- Download give MySQL dump file from Object Storage
- Search for `SOURCE_LOG_FILE` and `SOURCE_LOG_POS` values
- Download MySQL binary logs files starting from `SOURCE_LOG_FILE`
- Load dump file, then load bin log files using `mysqlbinlog` tool (up to `SOURCE_LOG_STOP_DATETIME`)

During the restore process apps should not connect to this database instance of course.

See `install-mysql-restore.sh` script to deploy (in a new namespace).

## Additional

See two simple scripts to insert data into MySQL:
- `deploy-app`: Job with a Python script to periodically insert data into a `message` table. It's useful to test Point In Time Recovery for example.
- `load-data`: Job to generate GBs of data in a `data` table. Could be used to test backup/restore time for larger databases.
