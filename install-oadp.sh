OPERATOR_OADP_NAMESPACE=openshift-adp
NAMESPACE=mysql
RESTORE_NAMESPACE=mysql-restore

# Install operator
oc apply -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/subscription.yaml

# Create GCP secret
oc apply -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/secret-gcp-credentials.yaml

# Setup backup locations
oc apply -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/dataprotectionapplication.yaml

# Check replication status
oc exec -n $NAMESPACE -c mysql test-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"'
# Using generateName for Backup, as it must be unique
# Create backup for namespace 
oc create -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/backup.yaml

# Run restore
oc delete project $RESTORE_NAMESPACE
oc delete -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/restore.yaml
# Restores are automatically removed when the related Backup expires
oc create -n $OPERATOR_OADP_NAMESPACE -f backup-oadp/restore.yaml
# Wait for namespace and pods
until oc get namespace $RESTORE_NAMESPACE && oc get -n $RESTORE_NAMESPACE pod/test-mysql-primary-0 && oc get -n $RESTORE_NAMESPACE pod/test-mysql-secondary-0; do
    sleep 1
done
oc wait -n $RESTORE_NAMESPACE --for=condition=Ready pod/test-mysql-primary-0
oc wait -n $RESTORE_NAMESPACE --for=condition=Ready pod/test-mysql-secondary-0

# Delete VolumeSnapshots after restore, because otherwise they are included in next backup, which causes problems!
# VolumeSnapshotContents will still stay, because Velero sets "deletionPolicy: Retain"
# It's also safe to delete both. The backend snapshot is still not removed until the Backup expires.
oc get -n $RESTORE_NAMESPACE volumesnapshot && oc get volumesnapshotcontents
vsclist=$(oc get -n $RESTORE_NAMESPACE -oname volumesnapshots)
for vsc in $vsclist; do # NOTE: Needs ${=vsclist} in zsh
  oc delete -n $NAMESPACE VolumeSnapshot $(basename $vsc)
  oc delete VolumeSnapshotContent $(basename $vsc)
done

# Check replication status
oc exec -n $RESTORE_NAMESPACE -c mysql test-mysql-secondary-0 -- /bin/bash -c 'mysql -u root -p$(cat $MYSQL_MASTER_ROOT_PASSWORD_FILE) --vertical <<<"SHOW REPLICA STATUS;"'