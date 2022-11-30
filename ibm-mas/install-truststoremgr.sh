#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

# Note:
# This installer only installs the ibm-truststore-mgr operator.

VERSION="${TM_VERSION:-1.2.1}"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/truststoremgr" && pwd )"

# Terminal colours
RED="\033[31m"
GREEN="\033[32m"
OFF="\033[0m"

# Set default options
LOG_DIR=${DIR}/logs

# USERNAME can be overridden to "iamapikey"
ICR_CPOPEN="${ICR_CPOPEN:-icr.io/cpopen}"


function showHelp {

  cat << EOM
Maximo Application Suite Installer $VERSION

Environment Variables:
+-----------------+----------------------------------------------------------+
| Name            | Description                                              |
+-----------------+----------------------------------------------------------+
| ICR_CPOPEN      | set an alternative registry for cpopen content           |
+-----------------+----------------------------------------------------------+


Usage:
  install.sh [flags]

Flags:
  -h, --help                          display help for installer
  -n, --namespace                     set namespace for this installation
EOM

}

# Process command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"
    shift
    case $key in
        -h|--help)
        showHelp
        exit 0
        ;;

        -n|--namespace)
        TM_NAMESPACE=$1
        shift
        ;;

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

function installCRD {
  # example:
  #   installCRD monitorapps.mas.ibm.com deploy/crds/mas.ibm.com_monitorapps_crd.yaml
  CRD_NAME=$1
  CRD_FILE=$2

  echo " - Installing ${CRD_NAME} CRD"
  oc apply -f ${CRD_FILE} >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to install ${CRD_NAME}.  See install log for details"
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
mkdir -p $DIR/logs
LOG_FILE=$LOG_DIR/install-tm.log

h1 "IBM Truststore Manager Operator Installer $VERSION"
if [ -z ${TM_NAMESPACE+x} ]; then
  echo -ne " - Namespace: > "
  read TM_NAMESPACE
fi

echo " - Kubernetes Namespace ... $TM_NAMESPACE"
echo " - Install Direction ...... $DIR"
echo " - Log File ............... $LOG_FILE"


# 2. Pre-req checks
# -----------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || { echo >&2 "Required executable \"oc\" not found on PATH.  Aborting."; exit 1; }

oc whoami &> /dev/null
if [[ "$?" == "1" ]]; then
  echo "You must be logged in to your OpenShift cluster to proceed (oc login)"
  exit 1
fi

# 3. Set up the namespace
# -----------------------------------------------------------------------------
oc project ${TM_NAMESPACE} >> ${LOG_FILE} 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${TM_NAMESPACE} >> ${LOG_FILE} 2>&1
fi


# 4. Install the Truststore Manager Operator
# -----------------------------------------------------------------------------
h2 "Install IBM Truststore Manager Operator"

OP_FILE=${DIR}/deploy/my_operator.yaml

sed -e "s|{{ICR_CPOPEN}}|${ICR_CPOPEN}|g" \
    -e "s|{{VERSION}}|${VERSION}|g" \
    ${DIR}/deploy/operator.yaml > ${OP_FILE}

installCRD truststores.truststore-mgr.ibm.com ${DIR}/deploy/crds/truststore-mgr.ibm.com_truststores.yaml

echo " - Installing Service Account"
oc apply -f ${DIR}/deploy/service_account.yaml -n ${TM_NAMESPACE}  >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply service account" ${LOG_FILE}
oc apply -f ${DIR}/deploy/worker_service_account.yaml -n ${TM_NAMESPACE}  >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply service account" ${LOG_FILE}

echo " - Installing Role"
oc apply -f ${DIR}/deploy/role.yaml -n ${TM_NAMESPACE}  >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply role" ${LOG_FILE}
oc apply -f ${DIR}/deploy/worker_role.yaml -n ${TM_NAMESPACE}  >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply role" ${LOG_FILE}

echo " - Installing Role Binding"
oc apply -f ${DIR}/deploy/role_binding.yaml -n ${TM_NAMESPACE} >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply role binding" ${LOG_FILE}
oc apply -f ${DIR}/deploy/worker_role_binding.yaml -n ${TM_NAMESPACE} >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply role binding" ${LOG_FILE}

echo " - Installing Controller Manager Deployment"
oc apply -f ${OP_FILE} -n ${TM_NAMESPACE} >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to apply truststore-mgr operator" ${LOG_FILE}

echo ""

echo -e "${GREEN}Truststore Manager Operator Installation Complete${OFF}"
