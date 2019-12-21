#!/usr/bin/env bash
set -euo pipefail
set -x

export GH_USERNAME="cjxd-bot-test"
export GH_OWNER="cb-kubecd"
export GH_EMAIL="jenkins-x@googlegroups.com"

# fix broken `BUILD_NUMBER` env var
export BUILD_NUMBER="$BUILD_ID"

JX_HOME="/tmp/jxhome"
KUBECONFIG="/tmp/jxhome/config"

# lets avoid the git/credentials causing confusion during the test
export XDG_CONFIG_HOME=$JX_HOME

mkdir -p $JX_HOME/git

jx --version
# replace the credentials file with a single user entry
echo "https://$GH_USERNAME:$GH_ACCESS_TOKEN@github.com" > $JX_HOME/git/credentials

# setup GCP service account
gcloud auth activate-service-account --key-file $GKE_SA

# setup git 
git config --global --add user.name CJXDBot
git config --global --add user.email jenkins-x@googlegroups.com

echo "running the BDD tests with JX_HOME = $JX_HOME"

# setup jx boot parameters
export JX_REQUIREMENT_ENV_GIT_PUBLIC=true
export JX_REQUIREMENT_GIT_PUBLIC=true
export JX_REQUIREMENT_ENV_GIT_OWNER="$GH_OWNER"
export JX_REQUIREMENT_PROJECT="jenkins-x-bdd3"
export JX_REQUIREMENT_ZONE="europe-west1-c"
export JX_VALUE_ADMINUSER_PASSWORD="$JENKINS_PASSWORD"
export JX_VALUE_PIPELINEUSER_USERNAME="$GH_USERNAME"
export JX_VALUE_PIPELINEUSER_EMAIL="$GH_EMAIL"
export JX_VALUE_PIPELINEUSER_TOKEN="$GH_ACCESS_TOKEN"
export JX_VALUE_PROW_HMACTOKEN="$GH_ACCESS_TOKEN"

# TODO temporary hack until the batch mode in jx is fixed...
export JX_BATCH_MODE="true"


mkdir boot-source
cd boot-source

PREVIOUS_JX_DOWNLOAD_LOCATION=$(git show origin/master:../jx/CJXD_LOCATION_LINUX)
JX_DOWNLOAD_LOCATION=$(<../jx/CJXD_LOCATION_LINUX)

wget $PREVIOUS_JX_DOWNLOAD_LOCATION
tar -zxvf jx-linux-amd64.tar.gz
export JX_BIN_DIR=$(pwd)
export PATH=$JX_BIN_DIR:$PATH


mkdir next_js_bin
cd next_js_bin
wget $JX_DOWNLOAD_LOCATION
tar -zxvf jx-linux-amd64.tar.gz
export JX_UPGRADE_BIN_DIR=$(pwd)
cd ..

echo "Starting with binary from $PREVIOUS_JX_DOWNLOAD_LOCATION"
echo "Upgrading using binary from $JX_DOWNLOAD_LOCATION"

sed -i "/^ *versionStream:/,/^ *[^:]*:/s/ref: .*/ref: master/" ../jx/bdd/boot-gke-vault-upgrade/jx-requirements.yml

echo "Using ../jx/bdd/boot-gke-vault-upgrade/jx-requirements.yml"
cat ../jx/bdd/boot-gke-vault-upgrade/jx-requirements.yml



cp ../jx/bdd/boot-gke-vault-upgrade/jx-requirements.yml .

# TODO hack until we fix boot to do this too!
helm init --client-only
helm repo add jenkins-x https://storage.googleapis.com/chartmuseum.jenkins-x.io

jx step bdd \
    --config ../jx/bdd/boot-gke-vault-upgrade/cluster.yaml \
    --gopath /tmp \
    --git-provider=github \
    --git-username $GH_USERNAME \
    --git-owner $GH_OWNER \
    --git-api-token $GH_ACCESS_TOKEN \
    --default-admin-password $JENKINS_PASSWORD \
    --no-delete-app \
    --no-delete-repo \
    --tests install \
    --tests test-verify-pods \
    --tests test-upgrade-boot \
    --tests test-verify-pods \
    --tests test-create-spring