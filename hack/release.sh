#!/usr/bin/env bash

# Copyright 2018 The Knative Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

source $(dirname $0)/../vendor/github.com/knative/test-infra/scripts/release.sh

# Set default GCS/GCR
: ${BUILD_RELEASE_GCS:="knative-nightly/build"}
: ${BUILD_RELEASE_GCR:="gcr.io/knative-nightly"}
readonly BUILD_RELEASE_GCS
readonly BUILD_RELEASE_GCR

# Local generated yaml file
readonly OUTPUT_YAML=release.yaml

# Set the repository
export KO_DOCKER_REPO=${BUILD_RELEASE_GCR}

# Script entry point

initialize $@

set -o errexit
set -o pipefail

run_validation_tests ./test/presubmit-tests.sh

banner "Building the release"

# Location of the base image for creds-init and git images
readonly BUILD_BASE_GCR="${KO_DOCKER_REPO}/github.com/knative/build/build-base"

# Build should not try to deploy anything, use a bogus value for cluster.
export K8S_CLUSTER_OVERRIDE=CLUSTER_NOT_SET
export K8S_USER_OVERRIDE=USER_NOT_SET
export DOCKER_REPO_OVERRIDE=DOCKER_NOT_SET

echo "- Destination GCR: ${KO_DOCKER_REPO}"
if (( PUBLISH_RELEASE )); then
  echo "- Destination GCS: ${BUILD_RELEASE_GCS}"
fi

# When building a versioned release, we must use .ko.yaml.release
if (( BRANCH_RELEASE )); then
  # KO_CONFIG_PATH expects a path containing a .ko.yaml file
  export KO_CONFIG_PATH="$(mktemp -d)"
  cp .ko.yaml.release "${KO_CONFIG_PATH}/.ko.yaml"
  echo "Using .ko.yaml.release for base image overrides"
fi

# Build the base image for creds-init and git images.
docker build -t ${BUILD_BASE_GCR} -f images/Dockerfile images/

echo "Building build-crd"
ko resolve ${KO_FLAGS} -f config/ > ${OUTPUT_YAML}
tag_images_in_yaml ${OUTPUT_YAML} ${KO_DOCKER_REPO} ${TAG}

echo "New release built successfully"

if (( ! PUBLISH_RELEASE )); then
 exit 0
fi

# Push the base image for creds-init and git images.
echo "Pushing base images to ${BUILD_BASE_GCR}"
docker push ${BUILD_BASE_GCR}

echo "Publishing ${OUTPUT_YAML}"
publish_yaml ${OUTPUT_YAML} ${BUILD_RELEASE_GCS} ${TAG}

branch_release "Knative Build" "${OUTPUT_YAML}"

echo "New release published successfully"

# TODO(mattmoor): Create other aliases?
