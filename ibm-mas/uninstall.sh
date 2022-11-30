#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2020, 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

VERSION="${MAS_VERSION:-8.6.0}"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
MAS_NAMESPACE="mas-${INSTANCE_ID}-core"

# Set default options
LOG_DIR=logs

function showHelp {

  cat << EOM
Maximo Application Suite Uninstaller $VERSION

Usage:
  uninstall.sh [flags]

Flags:
      --silent                      accept the uninstall without prompting for user input, note: it does NOT wipe data
      --silent-wipe-data              accept the uninstall without prompting for user input, note: it DOES wipe data
      --remove-cluster-role         remove Cluster Role from the cluster. It might affect other instances of MAS
  -h, --help                        help for installer
  -i, --instance-name               if set, override the default instance name ("local") used by the installer
  -l, --log-dir string              write log files to this directory

EOM
}

# Process command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -h|--help)
        showHelp
        exit 0
        ;;

        -i|--instance-name)
        INSTANCE_ID=$2
        ;;

        -l|--log-dir)
        LOG_DIR=$2
        ;;

        --silent)
        SILENT=1
        ;;

        --silent-wipe-data)
        SILENT_WIPEDATA=1
        ;;

        --remove-cluster-role)
        REMOVE_CLUSTER_ROLE=1
        ;;

        *)
        # unknown option
        ;;
    esac
    shift
done

function h1 {
  echo ""
  echo "======================================================================"
  echo $1
  echo "======================================================================"
}

function h2 {
  echo ""
  echo $1
  echo "----------------------------------------------------------------------"
}

function showWorking {
  # Usage: run any command in the background, capture it's PID
  #
  # somecommand >> ${LOG_FILE} 2>&1 &
  # showWorking $!
  #
  PID=$1

  sp='/-\|'
  printf ' '
  while s=`ps -p $PID`; do
    printf '\b%.1s' "$sp"
    sp=${sp#?}${sp%???}
    sleep 0.1s
  done
  printf '\b '
}


function logAndDeleteProject {
  PROJECT_NAME=$1
  echo " - Deleting mas-${INSTANCE_ID}-${PROJECT_NAME}"
  oc delete project "mas-${INSTANCE_ID}-${PROJECT_NAME}" >> ${LOG_FILE} 2>&1
  if [ "$?" != 0 ]; then
    echo -e "    - ${RED}Deletion failed${OFF}"
  fi
}


RED="\033[31m"
GREEN="\033[32m"
OFF="\033[0m"


# Pre-req checks
# - check oc command on path
command -v oc >/dev/null 2>&1 || { echo >&2 "Required executable \"oc\" not found on PATH.  Aborting."; exit 1; }

# Confirm user is logged in to the OpenShift cluster already
oc whoami &> /dev/null
if [[ "$?" == "1" ]]; then
  echo "You must be logged in to your OpenShift cluster to proceed (oc login)"
  exit 1
fi

# Create directory for logs
mkdir -p $LOG_DIR

LOG_FILE=$LOG_DIR/uninstall-mascore.log


h1 "Maximo Application Suite Uninstaller $VERSION"
echo " - Instance Name:  $INSTANCE_ID"
echo " - Debug Log:  $LOG_FILE"

# =====================================================================================================================
# Monitor
# =====================================================================================================================
h1 "1. Monitor Application"
echo "This can take a number of minutes to complete.."
oc delete -n mas-${INSTANCE_ID}-monitor monitorapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-monitor
oc delete configmaps --all -n mas-${INSTANCE_ID}-monitor

# =====================================================================================================================
# IoT
# =====================================================================================================================
h1 "2. IoT Application"
echo "This can take 15-25 minutes to complete.."
oc delete -n mas-${INSTANCE_ID}-iot iot ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-iot
oc delete configmaps --all -n mas-${INSTANCE_ID}-iot

# =====================================================================================================================
# Predict
# =====================================================================================================================
h1 "3. Predict Application"
oc delete -n mas-${INSTANCE_ID}-predict predictapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-predict
oc delete configmaps --all -n mas-${INSTANCE_ID}-predict

# =====================================================================================================================
# Health - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 "4. Health Application"
echo "This can take a few minutes to complete.."
oc delete --all -n mas-${INSTANCE_ID}-health healthworkspace
oc delete --all -n mas-${INSTANCE_ID}-health manageserverbundle
oc delete --all -n mas-${INSTANCE_ID}-health managedeployment
oc delete --all -n mas-${INSTANCE_ID}-health managebuild
oc delete -n mas-${INSTANCE_ID}-health healthapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-health
oc delete configmaps --all -n mas-${INSTANCE_ID}-health
#oc delete validatingwebhookconfiguration ibm-mas-health-webhook-${INSTANCE_ID}

# =====================================================================================================================
# Manage - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 "5. Manage Application"
echo "This can take a few minutes to complete.."
oc delete --all -n mas-${INSTANCE_ID}-manage manageworkspace
oc delete --all -n mas-${INSTANCE_ID}-manage manageserverbundle
oc delete --all -n mas-${INSTANCE_ID}-manage managedeployment
oc delete --all -n mas-${INSTANCE_ID}-manage managebuild
oc delete -n mas-${INSTANCE_ID}-manage manageapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-manage
oc delete configmaps --all -n mas-${INSTANCE_ID}-manage
#oc delete validatingwebhookconfiguration ibm-mas-manage-webhook-${INSTANCE_ID}

# =====================================================================================================================
# Scheduler Optimization - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 "5. Scheduler Optimization Application"
echo "This can take a few minutes to complete.."
oc delete --all -n mas-${INSTANCE_ID}-mso msoworkspace
oc delete -n mas-${INSTANCE_ID}-mso msoapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-mso
oc delete configmaps --all -n mas-${INSTANCE_ID}-mso

# =====================================================================================================================
# VisualInspection - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 "6. VisualInspection Application"
oc delete -n mas-${INSTANCE_ID}-visualinspection visualinspectionapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-visualinspection
oc delete configmaps --all -n mas-${INSTANCE_ID}-visualinspection

# =====================================================================================================================
# Assist - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 "7. Assist Application"
echo "This can take 15-25 minutes to complete.."
oc delete -n mas-${INSTANCE_ID}-assist assistapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-assist
oc delete configmaps --all -n mas-${INSTANCE_ID}-assist

# =====================================================================================================================
# HPUtilities - Delete the app including all secrets and configMaps
# =====================================================================================================================
h1 " HPUtilities Application"
echo "This can take 15-25 minutes to complete.."
oc delete -n mas-${INSTANCE_ID}-hputilities hputilitiesapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-hputilities
oc delete configmaps --all -n mas-${INSTANCE_ID}-hputilities

# =====================================================================================================================
# Safety
# =====================================================================================================================
h1 "8. Safety Application"
oc delete -n mas-${INSTANCE_ID}-safety safetyapp ${INSTANCE_ID}
oc delete secrets --all -n mas-${INSTANCE_ID}-safety
oc delete configmaps --all -n mas-${INSTANCE_ID}-safety

# =====================================================================================================================
# SLS
# =====================================================================================================================
h1 "9. Suite Licensing Service"
oc delete -n mas-${INSTANCE_ID}-sls licenseservice sls
oc delete secrets --all -n mas-${INSTANCE_ID}-sls
oc delete configmaps --all -n mas-${INSTANCE_ID}-sls

# =====================================================================================================================
# Core
# =====================================================================================================================
h1 "10. Core Services"

h2 "10.1 Wipe Data"
if [ "${SILENT}" == "1" ]; then
  echo -e "Skipping wipe data for silent uninstall"
else
  echo ""
  if [ "${SILENT_WIPEDATA}" == "1" ]; then
    echo -e "Silently wipe data"
    oc exec -it -n mas-$INSTANCE_ID-core $(oc get pods -n mas-$INSTANCE_ID-core -l app=$INSTANCE_ID-coreapi -o=jsonpath='{.items[0].metadata.name}') python3 /opt/ibm/coreapi/wipeData.py silent-wipe-data
  else
    oc exec -it -n mas-$INSTANCE_ID-core $(oc get pods -n mas-$INSTANCE_ID-core -l app=$INSTANCE_ID-coreapi -o=jsonpath='{.items[0].metadata.name}') python3 /opt/ibm/coreapi/wipeData.py
    if [ -z $STRIMZI_NAMESPACE ] ; then
      echo "If using Strimzi, provide the namespace of your Strimzi deployment to "
      echo "automatically delete all the topics used by this MAS instance, leave "
      echo "empty to continue without cleaning up the topics.  "
      echo ""
      echo "At present this uninstall only supports cleaning up kafka topics if "
      echo "you used the strimzi operator."
      echo ""
      echo -n "Strimzi Namespace: "
      read STRIMZI_NAMESPACE
    fi
  fi
  if [[ "$STRIMZI_NAMESPACE" != "" ]] ; then
    # Wipe Kafka topics
    oc -n $STRIMZI_NAMESPACE delete kafkatopics $(oc get kafkatopics -n $STRIMZI_NAMESPACE | grep $INSTANCE_ID | awk '{print $1}')
  fi
fi

h2 "10.2 Maximo Application Suite CR \"${INSTANCE_ID}\""
oc delete -n mas-${INSTANCE_ID}-core suite ${INSTANCE_ID}

h2 "10.2.1 Delete completed pods \"${INSTANCE_ID}\""
oc delete pod --field-selector=status.phase==Succeeded -n mas-${INSTANCE_ID}-core

# Note: there will be two pods left (the suite and truststore operator pods), and we have to count the table header too
echo ""
echo -n "Waiting for all pods to terminate (core)  "
while [ $(oc get pods -n mas-${INSTANCE_ID}-core 2> /dev/null | wc -l) -ge 4 ]; do
  sleep 5s
done &
showWorking $!

echo ""
h2 "10.3 Operator Deployment"
oc delete deployment ibm-mas-operator -n mas-${INSTANCE_ID}-core

h2 "10.4 Truststore Manager Operator Deployment"
oc delete deployment ibm-truststore-mgr-operator -n mas-${INSTANCE_ID}-core

h2 "10.5 Service Account"
oc delete serviceaccount ibm-mas-operator -n mas-${INSTANCE_ID}-core

h2 "10.6 Secrets"
oc delete secrets --all -n mas-${INSTANCE_ID}-core

h2 "10.7 Config Maps"
oc delete configmaps --all -n mas-${INSTANCE_ID}-core

h2 "10.8 Internal ClusterIssue"
oc delete clusterissuer mas-${INSTANCE_ID}-ca
oc delete clusterissuer mas-${INSTANCE_ID}-core-internal-ca-issuer

h2 "10.9 External Self-signed ClusterIssue"
oc delete clusterissuer mas-${INSTANCE_ID}-core-public-ca-issuer

h2 "10.10 Internal CA cert-manager secret"
oc delete certificates ${INSTANCE_ID}-cert-internal-ca -n cert-manager
oc delete secret ${INSTANCE_ID}-cert-internal-ca -n cert-manager

h2 "10.11 External CA cert-manager secret"
oc delete certificates ${INSTANCE_ID}-cert-public-ca -n cert-manager
oc delete secret ${INSTANCE_ID}-cert-public-ca -n cert-manager

h2 "10.12 Removing Cluster Role Binding"
oc delete clusterrolebinding ibm-mas-app-reader:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-coreapi-base:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-assist:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-hputilities:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-iot:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-manage:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-monitor:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-predict:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-safety:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-visualinspection:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-deployer-mso:${INSTANCE_ID}
oc delete clusterrolebinding ibm-mas-operator:${INSTANCE_ID}

h2 "10.12.1 Removing Cluster roles"
oc delete clusterroles ibm-mas-app-reader:${INSTANCE_ID}
oc delete clusterroles ibm-mas-coreapi-base:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-assist:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-hputilities:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-iot:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-manage:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-monitor:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-predict:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-safety:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-visualinspection:${INSTANCE_ID}
oc delete clusterroles ibm-mas-deployer-mso:${INSTANCE_ID}
oc delete clusterroles ibm-mas-operator:${INSTANCE_ID}

h2 "10.13 Removing Suite ValidatingWebhookConfiguration"
oc delete validatingwebhookconfiguration ibm-mas-operator-webhook-${INSTANCE_ID}
oc delete validatingwebhookconfiguration ibm-mas-manage-webhook-${INSTANCE_ID}

h1 "11. OpenShift Projects"
logAndDeleteProject core
logAndDeleteProject iot
logAndDeleteProject monitor
logAndDeleteProject predict
logAndDeleteProject health
logAndDeleteProject manage
logAndDeleteProject visualinspection
logAndDeleteProject assist
logAndDeleteProject hputilities
logAndDeleteProject safety
logAndDeleteProject sls
logAndDeleteProject mso

echo ""
echo -e "${GREEN}MAS Uninstallation complete${OFF}"
