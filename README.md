## Deploy MySql with Bitnami Helm chart

Helm chart source: https://github.com/bitnami/charts/tree/main/bitnami/mysql
Container image source: https://github.com/bitnami/containers/tree/main/bitnami/mysql

Build image
```
cd containers/bitnami/mysql/9.6/debian-12
# For Podman had to remove line "--mount=type=secret,id=downloads_url,env=SECRET_DOWNLOADS_URL", see https://github.com/containers/buildah/pull/6285
podman build --arch amd64 --format docker -t quay.io/bszeti/mysql:9.6 .
```

Install:
```
oc new-project mysql
helm upgrade -i -n mysql test oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-cluster.yaml
oc logs -f test-mysql-primary-0

# With Sidecar
helm upgrade -i -n mysql test oci://registry-1.docker.io/bitnamicharts/mysql -f deploy-mysql/values-sidecar.yaml
oc logs -f test-mysql-secondary-0 -c backup-mysql-bin
oc rsh -c backup-mysql-bin test-mysql-secondary-0
```

Connect with mysql:
```
mysql -u root -p$(cat $MYSQL_ROOT_PASSWORD_FILE) <<<"SHOW DATABASES;"
```

Backup:
```
oc apply -f deploy-mysql/cronjob.yaml
```

Restore:
```
### gcloud container

# Download mysql dump
mkdir -p /tmp/restore/mysql-dump
gcloud auth activate-service-account --key-file=/gcp-credentials/sa.json
gcloud storage cp gs://my-bucket-n9dps/mysql-test/cf6a99d4-287e-11f1-b05a-0a580a83002c/mysql-dump/mysqldump-2026-03-26-15-55-00.sql.gz /tmp/restore/mysql-dump/

change_replication_line=$(gzip -d --stdout ./mysqldump-2026-03-26-15-55-00.sql.gz | grep -m 1 "CHANGE REPLICATION SOURCE TO")
echo $change_replication_line # CHANGE REPLICATION SOURCE TO SOURCE_LOG_FILE='mysql-bin.000589', SOURCE_LOG_POS=238;
REGEXP="^.*SOURCE_LOG_FILE='([^']+).*SOURCE_LOG_POS=([^;]+)"
if [[ $change_replication_line =~ $REGEXP ]]; then
    # Assign matches to your variables
    SOURCE_LOG_FILE="${BASH_REMATCH[1]}"
    SOURCE_LOG_POS="${BASH_REMATCH[2]}"
    echo -e "SOURCE_LOG_FILE=$SOURCE_LOG_FILE\nSOURCE_LOG_POS=$SOURCE_LOG_POS" >/tmp/restore/mysql-dump/source_log
    cat /tmp/restore/mysql-dump/source_log
else
   echo "Can't find SOURCE_LOG_FILE or SOURCE_LOG_POS in mysqldump line: $change_replication_line"
   exit 1
fi
SHARED_DIR=/backup/upload
mv /tmp/restore/mysql-dump $SHARED_DIR

# Download mysql bins
BACKUP_BUCKET_PATH=gs://my-bucket-n9dps/mysql-test/cf6a99d4-287e-11f1-b05a-0a580a83002c
BIN_FILES_IN_BUCKET=$(gcloud storage ls "$BACKUP_BUCKET_PATH/mysql-bin/*")
echo $BIN_FILES_IN_BUCKET

BIN_FILES_MIN_INDEX=$((10#${SOURCE_LOG_FILE##*.}))
BIN_FILES_REQUIRED=()
for binfile in $BIN_FILES_IN_BUCKET; do
  # Extract the extension, remove leading zeros 
  index=$((10#${binfile##*.}))
  if (( index >= BIN_FILES_MIN_INDEX )); then
    # echo "$index required"
    BIN_FILES_REQUIRED+=("$binfile")
  fi
done
echo "Required mysql-bin files":
printf '%s\n' "${BIN_FILES_REQUIRED[@]}"

mkdir -p /tmp/restore/mysql-bin/
gcloud storage cp ${BIN_FILES_REQUIRED[*]} /tmp/restore/mysql-bin/
ls /tmp/restore/mysql-bin/
mv /tmp/restore/mysql-bin $SHARED_DIR


### mysql container
MYSQL_SERVICE=restore-mysql-primary.mysql.svc
MYSQL_ROOT_PASSWORD_FILE=/tmp/mysql-credentials/mysql-root-password
MYSQL_DUMP_DIR=/backup/upload/mysql-dump
MYSQL_BIN_DIR=/backup/upload/mysql-bin

# Load mysql dump
while [ -z "$(ls -A $MYSQL_DUMP_DIR)" ]; do
    echo "Waiting for mysql-dump"
    sleep 5
done
gzip -d --stdout $MYSQL_DUMP_DIR/mysqldump-*.sql.gz | mysql -h $MYSQL_SERVICE -u root -p$(cat $MYSQL_ROOT_PASSWORD_FILE)
mysql -h $MYSQL_SERVICE -u root -p$(cat $MYSQL_ROOT_PASSWORD_FILE) <<< "SHOW DATABASES;"
mysql -h $MYSQL_SERVICE -u root -p$(cat $MYSQL_ROOT_PASSWORD_FILE)  db1 <<< "SHOW TABLES;"

# Load mysql bin logs
while [ -z "$(ls -A $MYSQL_BIN_DIR)" ]; do
    echo "Waiting for mysql-dump"
    sleep 5
done

source $MYSQL_DUMP_DIR/source_log
MYSQL_BIN_FILES=$(find $MYSQL_BIN_DIR -type f | sort)
SOURCE_LOG_STOP_DATETIME="2026-03-26 17:00:00"
mysqlbinlog --no-defaults $MYSQL_BIN_FILES --start-position $SOURCE_LOG_POS "${SOURCE_LOG_STOP_DATETIME:+--stop-datetime}" "${SOURCE_LOG_STOP_DATETIME}" | cat

```