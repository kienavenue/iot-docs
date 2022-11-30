#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------


OPERATOR_CHANNEL=${OPERATOR_CHANNEL:-preview}
OPERATOR_VERSION=${OPERATOR_VERSION:-0.8.0}

OPERATOR_CATALOG_NAMESPACE="openshift-marketplace"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SBO_DIR="${DIR}/sboinstall"

# Terminal colours
RED="\033[31m"
GREEN="\033[32m"
OFF="\033[0m"

# Set default options
mkdir -p ${SBO_DIR}/logs
LOG_DIR=${SBO_DIR}/logs

function showHelp {

  cat << EOM
Service Binding Operator Install

Environment Variables:
+------------------+---------------------------------------------------------+
| Name             | Description                                             |
+------------------+---------------------------------------------------------+
| OPERATOR_CHANNEL | Service Binding Operator Catalog Channel                |
| OPERATOR_VERSION | The version of the Service Binding Operator to install  |
+------------------+---------------------------------------------------------+

Usage:
  install-sbo.sh

EOM

}

# Process command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"
    shift
    case $key in
        
        *)
        # unknown option
        echo -e "\n${RED}Usage Error: Unsupported flag \"${key}\" ${OFF}\n\n"
        showHelp
        exit 1
        ;;
    esac
done

function h1 {
  echo ""
  echo $1
  echo "======================================================================"
}

function h2 {
  echo ""
  echo $1
  echo "----------------------------------------------------------------------"
}

function logFailureAndExit {
  echo -e "\n${RED}$1${OFF}"
  if [[ -z $2 ]]; then
    echo -e
  else
    echo -e "${RED}See ${2} for more information.${OFF}\n"
  fi
  exit 1
}


# 1. Set up
# -----------------------------------------------------------------------------

LOG_FILE=${LOG_DIR}/install-sbo.log

h1 "Service Binding Operator Installer"

echo " - Service Binding Operator Channel ... ${OPERATOR_CHANNEL}"
echo " - Service Binding Operator Version ...... ${OPERATOR_VERSION}"
echo " - Log File ............... ${LOG_FILE}"


# 2. Pre-req checks
# -----------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || { echo >&2 "Required executable \"oc\" not found on PATH.  Aborting."; exit 1; }

oc whoami &> /dev/null
if [[ "$?" == "1" ]]; then
  echo "You must be logged in to your OpenShift cluster to proceed (oc login)"
  exit 1
fi


function waitForTheInstallPlan {
  echo -n " - Searching for install plan  "
  retries=50
  until [[ $retries == 0 ]]; do
      INSTALL_PLAN=$(oc get installplan -n openshift-operators  --ignore-not-found  -l "operators.coreos.com/rh-service-binding-operator.openshift-operators="   -o 'jsonpath={..metadata.name}') 2>> ${LOG_FILE}
      echo ${INSTALL_PLAN} >> ${LOG_FILE}
      if [[ -z ${INSTALL_PLAN} ]]; then
          echo -n  "."
      else
          CSV=$(oc get installplan $INSTALL_PLAN -n openshift-operators -o 'jsonpath={..spec.clusterServiceVersionNames[0]}') 2>> ${LOG_FILE}
          echo "CSV found: ${CSV}" >> ${LOG_FILE}
          if [[ $CSV == "service-binding-operator.v${OPERATOR_VERSION}" ]]; then
              echo " "
              break
          else
              unset INSTALL_PLAN
          fi
      fi
    sleep 5
    retries=$(($retries - 1))
    echo "No install plan found... Trying again." >> ${LOG_FILE}
  done
}


# 4. Install the Service Binding Operator
# -----------------------------------------------------------------------------
h2 "Install the Service Binding Operator"

SUB_EXISTS=$(oc get sub -n openshift-operators --ignore-not-found -l "operators.coreos.com/rh-service-binding-operator.openshift-operators=") 2>> ${LOG_FILE}

if [[ -z ${SUB_EXISTS} ]]; then
  echo "Creating subscription rh-service-binding-operator"
  oc apply -f - << EOD
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rh-service-binding-operator
  namespace: openshift-operators
spec:
  channel: $OPERATOR_CHANNEL
  name: rh-service-binding-operator
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
  startingCSV: service-binding-operator.v$OPERATOR_VERSION
EOD

  waitForTheInstallPlan

  if [[ -z ${INSTALL_PLAN} ]]; then
      logFailureAndExit "No valid install plan was found for the Service Binding Operator." ${LOG_FILE}
  fi

  echo "Approving the install plan ${INSTALL_PLAN}"
  oc patch installplan ${INSTALL_PLAN} -n openshift-operators --type merge --patch '{"spec":{"approved":true}}' >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to patch install plan" ${LOG_FILE}

else
  logFailureAndExit "Subscription to rh-service-binding-operator aleady found.\nSkipping creation of the subscription to avoid duplicities." ${LOG_FILE}
fi

echo ""

echo -e "${GREEN}Service Bindign Operator Installation Complete${OFF}"