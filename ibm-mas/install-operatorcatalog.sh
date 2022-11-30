#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

# Note:
# This installer only installs the ibm operator catalog.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
OPERATOR_DIR="${DIR}/operatorcatalog"


OPERATOR_CATALOG_NAMESPACE="openshift-marketplace"

# Terminal colours
RED="\033[31m"
GREEN="\033[32m"
OFF="\033[0m"

# Set default options
LOG_DIR=${OPERATOR_DIR}/logs

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
mkdir -p $OPERATOR_DIR/logs
LOG_FILE=$LOG_DIR/install-catalog.log

h1 "IBM Operator Catalog Installer"

echo " - Kubernetes Namespace ... $OPERATOR_CATALOG_NAMESPACE"
echo " - Install Direction ...... $OPERATOR_DIR"
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
oc project ${OPERATOR_CATALOG_NAMESPACE} >> ${LOG_FILE} 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${OPERATOR_CATALOG_NAMESPACE} >> ${LOG_FILE} 2>&1
fi


# 4. Install the IBM Operator Catalog
# -----------------------------------------------------------------------------
h2 "Install IBM Operator Catalogs"

echo " - Installing IBM Operator Catalogs"
oc apply -f ${OPERATOR_DIR}/ibm-catalogs.yaml  >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to install IBM Operator catalog and Common service catalog" ${LOG_FILE}

echo ""

echo -e "${GREEN}IBM Operator Catalog and Common service catalog Installation Complete${OFF}"
