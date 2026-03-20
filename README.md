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
```

Connect with mysql:
```
mysql -u root -p$(cat $MYSQL_ROOT_PASSWORD_FILE) <<<"SHOW DATABASES;"
```

Backup:
```
oc apply -f deploy-mysql/cronjob.yaml
```