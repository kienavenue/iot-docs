#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

CERT_MANAGER_VERSION=${CERT_MANAGER_VERSION:-1.2.0}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CERT_MANAGER_DIR="${DIR}/certmgrinstall"

# Terminal colours
RED="\033[31m"
GREEN="\033[32m"
OFF="\033[0m"

# Set default options
mkdir -p ${CERT_MANAGER_DIR}/logs
LOG_DIR=${CERT_MANAGER_DIR}/logs

function showHelp {

  cat << EOM
Service Binding Operator Install

Environment Variables:
+-----------------------+----------------------------------------------------+
| Name                  | Description                                        |
+-----------------------+----------------------------------------------------+
| CERT_MANAGER_VERSION  | cert-manager version to install                    |
+-----------------------+----------------------------------------------------+

Usage:
  install-cert-manager.sh

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
LOG_FILE=${LOG_DIR}/install-cert-manager.log

h1 "cert-manager Installer"

echo " - cert-manager Version... ${CERT_MANAGER_VERSION}"
echo " - Log File ............... ${LOG_FILE}"

# 2. Pre-req checks
# -----------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || { echo >&2 "Required executable \"oc\" not found on PATH.  Aborting."; exit 1; }

oc whoami &> /dev/null
if [[ "$?" == "1" ]]; then
  echo "You must be logged in to your OpenShift cluster to proceed (oc login)"
  exit 1
fi

# 3. Install cert-manager
# -----------------------------------------------------------------------------
h2 "Install cert-manager"

oc new-project cert-manager >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to create namespace cert-manager" ${LOG_FILE}
oc apply -f https://github.com/jetstack/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml >> ${LOG_FILE} 2>&1 || logFailureAndExit "Unable to complete cert-manager install" ${LOG_FILE}

echo -e "${GREEN}cert-manager Installation Complete${OFF}"