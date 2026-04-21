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
- In case of connection issues the secondary node only reconnects for 10x10sec before giving up. This stops the replication, but not the instance. A custom `livenessProbe` is added to force restart if replication status in not OK.


## Backup using MySQL specific tools

The backup solution uses only the secondary node to make sure it's not affecting the primary node. It has two main components:
- A _CronJob_ taking `mysqldump` full dumps periodically (e.g. daily)
- Sidecars copying binary log files from the `data` directory periodically (e.g. hourly)

For a [Point In Time Recovery](https://medium.com/@nimishagarwal76/point-in-time-recovery-mysql-15ba57eccd9d) you need both a full dump and binary logs afterwards. The backup files are stored `gzip` compressed.

See `install-mysql.sh` script to deploy.


### Backup CronJob for mysql dump
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

## Backup with OpenShift ADP

The [backup-oadp](./backup-oadp) folder and related [install-oadp.sh](./install-oadp.sh) shows how to create a backup of our database with [Red Hat OpenShift APIs for Data Protection (OADP)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/backup_and_restore/oadp-application-backup-and-restore) which is a generic Kubernetes native backup solution based on the [Velero](https://velero.io/) tool.

This example uses [Google Cloud Object Storage](https://cloud.google.com/storage) to store K8s resources, while utilizes the cluster's CSI driver to create [VolumeSnapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/) of the `PersistentVolumes`. See the `DataProtectionApplication` examples how to configure one or multiple backup locations.

The [backup.yaml](backup-oadp/backup.yaml) creates snapshots of the PVs of both Pods. It's important to create a snapshot of the secondary instance first to avoid timeline issues after restore breaking the replication. The order is set in `orderedResources.pods` field. If the order is `secondary` then `primary`, the replication status should look OK after restoring.

With the tested [OADP version](https://github.com/openshift/oadp-operator#velero-version-relationship) (`v1.5` on OpenShift `v4.21`) we noticed that the restored `VolumeSnapshot` resources are kept in the namespace after the related `PersistentVolumes` are restored. This is confusing when we're trying to make backups again of the restored namespace, and it's recommended to delete them once we verified that the restore was successful (e.g. the Pods reached `Ready`). Deleting the `VolumeSnapshot` won't remove the actual snapshot in the backend, those are only removed when the `Backup` expires.

See [restore.yaml](backup-oadp/restore.yaml) how to restore an existing `Backup`. Set `namespaceMapping` to restore in another namespace.

Notes and Known Issues:
- A backup pre-hook is required to run `FLUSH TABLES WITH READ LOCK` before taking a snapshot to guarantee database level file consistency. This `mysql` session must be running after the hook is completed, otherwise the lock transaction status will be aborted. In this example we assume 60sec is enough for the CSI driver to create a snapshot and for OADP to kill the locking process in the post-hook. Any write operations from the apps are blocked during this timeframe.
- The backup pre-hook running the lock must be put in background, which results a zombie `mysql` process in the Pod once it's terminated.
- Deleting the backups manually (in Object Storage) doesn't remove the related snapshots - as that info was stored there. Meanwhile it's done properly when the `Backup` expires (checked every 1 hour by default).
- The `VolumeSnapshots` (and related `VolumeSnapshotContents`) are left in the namespace after Restore. Delete them before taking a next Backup, otherwise they start piling up.

## Additional

See two simple scripts to insert data into MySQL:
- `deploy-app`: Job with a Python script to periodically insert data into a `message` table. It's useful to test Point In Time Recovery for example.
- `load-data`: Job to generate GBs of data in a `data` table. Could be used to test backup/restore time for larger databases.

### Test app inserting rows

A simple Python test app can be found in [deploy-app](./deploy-app) folder, see [install-app.sh](./install-app.sh) to run it as a Kubernetes job. This app is useful to generate ongoing traffic meanwhile taking a backup and see what was included.

Main env vars:
- **MESSAGE_LENGTH**: Length of string to insert into a table row
- **BATCH_SIZE**: Number of rows to insert in one batch (transaction)
- **BATCH_COUNT**: Number of rounds, the Job is finished afterwards
- **SLEEP_MS**: Sleep time between rounds

### Load high volume of data

This [Job](./load-data/job-load-data.yaml) and related [load-data.sh](./load-data.sh) can be used to generate multiple gigabytes of data in a table. This is useful to test backup of large databases.

Main env vars:
- **DATA_SIZE_GB**: How many GBs of data do we want inject into the database

