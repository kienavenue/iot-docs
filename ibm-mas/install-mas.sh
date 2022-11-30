#!/bin/bash

# -----------------------------------------------------------
# Licensed Materials - Property of IBM
# 5737-M66, 5900-AAA
# (C) Copyright IBM Corp. 2020, 2021 All Rights Reserved.
# US Government Users Restricted Rights - Use, duplication, or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
# -----------------------------------------------------------

VERSION="${MAS_VERSION:-8.6.0}"
TM_VERSION="${TM_VERSION:-1.2.1}"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CLUSTER_ISSUER_RENEW="720h0m0s"  # 30 days
CLUSTER_ISSUER_DURATION="8760h0m0s" # 1 year

MAS_DIR="${DIR}/mas"
OC_DIR="${DIR}/operatorcatalog"
TM_DIR="${DIR}/truststoremgr/deploy"
ACCEPT_LICENSE=0

COLOR_RED=`tput setaf 1`
COLOR_GREEN=`tput setaf 2`
COLOR_YELLOW=`tput setaf 3`
COLOR_BLUE=`tput setaf 4`
COLOR_MAGENTA=`tput setaf 5`
COLOR_CYAN=`tput setaf 6`
COLOR_RESET=`tput sgr0`

function echo_h1() {
  echo ""
  echo "${COLOR_YELLOW}================================================================================"
  echo "$1"
  echo "================================================================================${COLOR_RESET}"
}

function echo_h2() {
  echo ""
  echo "$1"
  echo "--------------------------------------------------------------------------------"
}

function echo_warning() {
  echo "${COLOR_RED}$1${COLOR_RESET}"
}

function echo_highlight() {
  echo "${COLOR_CYAN}$1${COLOR_RESET}"
}

# USERNAME can be overridden to "iamapikey"
ICR_USERNAME="${ICR_USERNAME:-cp}"
ICR_CP="${ICR_CP:-cp.icr.io/cp}"
ICR_CPOPEN="${ICR_CPOPEN:-icr.io/cpopen}"

function showHelp {

  cat << EOM
Maximo Application Suite Installer $VERSION

Environment Variables:
+-----------------+----------------------------------------------------------+
| Name            | Description                                              |
+-----------------+----------------------------------------------------------+
| ENTITLEMENT_KEY | set the entitlement Key                                  |
| ICR_USERNAME    | set an alternative username for ICR                      |
| ICR_CP          | set an alternative registry for cp content               |
| ICR_CPOPEN      | set an alternative registry for cpopen content           |
+-----------------+----------------------------------------------------------+

Usage:
  install.sh [flags]

Flags:
  --accept-license                    accept the license terms without prompting for user input
  -c, --cluster-issuer                use this cert-manager ClusterIssuer to secure all routes
  --cluster-issuer-renew              use this to override renew before value for MAS public certificate, default is 720h0m0s, 30 days
  --cluster-issuer-duration           use this to override renew before value for MAS public certificate, default is 8760h0m0s, 1 year
  -d, --domain                        set the domain name to use in all routes
  -h, --help                          display help for installer
  -i, --instance-name                 set instance name (ID) for this installation
EOM

}

# Process command line arguments
while [[ $# -gt 0 ]]
do
    key="$1"
    shift
    case $key in
        -d|--domain)
        DOMAIN=$1
        shift
        ;;

        -h|--help)
        showHelp
        exit 0
        ;;

        --accept-license)
        ACCEPT_LICENSE=1
        ;;

        -i|--instance-name)
        INSTANCE_ID=$1
        shift
        ;;

        -c|--cluster-issuer)
        CLUSTER_ISSUER=$1
        shift
        ;;

        --cluster-issuer-renew)
        CLUSTER_ISSUER_RENEW=$1
        shift
        ;;

        --cluster-issuer-duration)
        CLUSTER_ISSUER_DURATION=$1
        shift
        ;;

        *)
        # unknown option
        echo -e "\n${COLOR_RED}Usage Error: Unsupported flag \"${key}\" ${COLOR_OFF}\n\n"
        showHelp
        exit 1
        ;;
    esac
done


function showWorking {
  # Usage: run any command in the background, capture it's PID
  #
  # somecommand >> /dev/null 2>&1 &
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

function logFailureAndExit {
  echo -e "\n${COLOR_RED}$1${COLOR_OFF}"
  if [[ -z $2 ]]; then
    echo -e
  else
    echo -e "${COLOR_RED}See ${2} for more information.${COLOR_OFF}\n"
  fi
  exit 1
}

function waitForRC {
  command=$1
  expectedRC=$2

  #Wait for the operator to get up and running
  retries=50
  until [[ $retries == 0 ]]; do
    result=$($command)
    rc=$?
    echo "$command = $rc"
    if [ "$rc" == "$expectedRC" ]; then
      break
    fi
    sleep 5
    retries=$(($retries - 1))
  done
}

function waitFor {
  command=$1
  expectedResult=$2

  #Wait for the operator to get up and running
  retries=50
  until [[ $retries == 0 ]]; do
    result=$($command)
    if [ "$result" == "$expectedResult" ]; then
      break
    fi
    sleep 5
    retries=$(($retries - 1))
  done
}

# 1. Display and prompt for license acceptance.
# License can also be accepted by providing the --accept-license command line flag
if [ -d license ]; then
  rm -rf license
fi

if [ "${ACCEPT_LICENSE}" == "1" ]; then
  echo "1" | java -jar ${DIR}/lap/LAPApp.jar -l ${DIR}/lap/language_licenseAgreement -s . -text_only; STATUS="${?}" 
  echo ""
  echo_highlight "License terms agreed to via --accept-license flag"
else
  java -jar ${DIR}/lap/LAPApp.jar -l ${DIR}/lap/language_licenseAgreement -s . -text_only; STATUS="${?}" 
fi
echo ""

## Acceptance validation 
if [[ "$STATUS" != 9 ]]; then
  echo_warning "Installation aborted because license terms were not accepted"
  exit 1
fi
echo_highlight "License information is available in the license/ directory"


# 2. Set up
# -----------------------------------------------------------------------------
echo_h1 "Maximo Application Suite Installer"
if [ -z ${INSTANCE_ID+x} ]; then
  echo -ne " - Instance ID: > "
  read INSTANCE_ID
fi

MAS_NAMESPACE="mas-${INSTANCE_ID}-core"
DISPLAY_NAME="MAS Core Systems (${INSTANCE_ID})"

echo "MAS version:                $VERSION"
echo "Truststore Manager version: $TM_VERSION"
echo "Instance ID:                $INSTANCE_ID"
echo "Namespace:                  $MAS_NAMESPACE"
echo "ICR cp content:             $ICR_CP"
echo "ICR cpopen content:         $ICR_CPOPEN"

# 3. Instance Name validation
# -----------------------------------------------------------------------------
if ! [[ "$INSTANCE_ID" =~ ^[a-z][a-z0-9\d-]{1,10}[a-z0-9]$ ]]; then
  echo -e "\n${COLOR_RED}Initialization Failed - Instance Name value is not valid ${COLOR_OFF}"
  cat << EOM
Instance Name expected format:
  * Alphanumeric characters plus the hyphen (-) special character
  * Cannot start with a number character
  * All lowercase characters
  * Must be 3 - 12 characters in length
EOM
  exit 1
fi


# 4. Pre-req checks
# -----------------------------------------------------------------------------
command -v oc >/dev/null 2>&1 || { echo >&2 "Required executable \"oc\" not found on PATH.  Aborting."; exit 1; }

oc whoami &> /dev/null
if [[ "$?" == "1" ]]; then
  echo "You must be logged in to your OpenShift cluster to proceed (oc login)"
  exit 1
fi


# 5. Collect required properties (if not provided in env vars)
# -----------------------------------------------------------------------------
if [ -z ${DOMAIN+x} ]; then
  SUBDOMAIN=$(oc get Ingress.config cluster -o jsonpath='{.spec.domain}')
  INGRESS_DOMAIN="${INSTANCE_ID}.${SUBDOMAIN}"

  echo ""
  echo -ne "Domain: (Default: $INGRESS_DOMAIN) > "
  read DOMAIN
  DOMAIN="${DOMAIN:=$INGRESS_DOMAIN}"
fi
echo "Using domain: ${DOMAIN}"    

if [ -z ${ENTITLEMENT_KEY+x} ]; then
  echo ""
  echo -ne "Entitlement Key: > "
  read -s ENTITLEMENT_KEY
fi
echo ""
echo_h2 "Switching to ${MAS_NAMESPACE} namespace"
echo ""
# 6. Create the project
# -----------------------------------------------------------------------------
oc project ${MAS_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project ${MAS_NAMESPACE} --display-name "${DISPLAY_NAME}" > /dev/null 2>&1
fi


# 7. Create/Recreate the ibm-entitlement secret
# -----------------------------------------------------------------------------
oc get secret ibm-entitlement -n ${MAS_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "0" ]]; then
  oc delete secret ibm-entitlement > /dev/null 2>&1
  if [[ "$?" == "1" ]]; then
    echo -e "\n${COLOR_RED}Initialization Failed - Unable to delete ibm-entitlement secret${COLOR_RESET}"
  fi
fi
oc create secret docker-registry ibm-entitlement \
  --docker-username=${ICR_USERNAME} \
  --docker-password="${ENTITLEMENT_KEY}" \
  --docker-server=${ICR_CP} -n ${MAS_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  echo -e "\n${COLOR_RED}Initialization Failed - Unable to create ibm-entitlement secret${COLOR_RESET}"
fi


# 8. Update the custom resource file for the appsuite operator
# -----------------------------------------------------------------------------
CR_FILE=${MAS_DIR}/my_core_v1_suite_cr.yaml

sed -e "s|{{INSTANCE_ID}}|${INSTANCE_ID}|g" \
    -e "s|{{DOMAIN}}|${DOMAIN}|g" \
    -e "s|{{CLUSTER_ISSUER}}|${CLUSTER_ISSUER}|g" \
    -e "s|{{ICR_CP}}|${ICR_CP}|g" \
    -e "s|{{ICR_CPOPEN}}|${ICR_CPOPEN}|g" \
    ${MAS_DIR}/core_v1_suite.yaml > ${CR_FILE}

if [ ! -z ${CLUSTER_ISSUER+x} ]; then
      cat << EOF >> $CR_FILE
  certificateIssuer:
    name: ${CLUSTER_ISSUER}
    renewBefore: ${CLUSTER_ISSUER_RENEW}
    duration: ${CLUSTER_ISSUER_DURATION}
EOF
fi

TMOP_FILE=${TM_DIR}/my_operator.yaml
sed -e "s|{{ICR_CPOPEN}}|${ICR_CPOPEN}|g" \
    -e "s|{{VERSION}}|${TM_VERSION}|g" \
    ${TM_DIR}/operator.yaml > ${TMOP_FILE}


# 9. Install (or update) IBM Truststore Manager operator
# -----------------------------------------------------------------------------
# TODO: Make truststore-mgr operator install work like MAS install
echo_h2 "1. Installing ibm-truststore-mgr operator"
TM_CRDS=${TM_DIR}/crds/*
for FILE in $TM_CRDS; do
  oc apply -f ${FILE} -n ${MAS_NAMESPACE} || logFailureAndExit "Unable to apply CRD ${FILE}"
done
oc apply -f ${TM_DIR}/role.yaml -n ${MAS_NAMESPACE}  || logFailureAndExit "Unable to apply truststore-mgr role"
oc apply -f ${TM_DIR}/role_binding.yaml -n ${MAS_NAMESPACE} || logFailureAndExit "Unable to apply truststore-mgr role binding"
oc apply -f ${TM_DIR}/service_account.yaml -n ${MAS_NAMESPACE}  || logFailureAndExit "Unable to apply truststore-mgr service account"
oc apply -f ${TM_DIR}/worker_role.yaml -n ${MAS_NAMESPACE}  || logFailureAndExit "Unable to apply truststore-mgr worker_role"
oc apply -f ${TM_DIR}/worker_role_binding.yaml -n ${MAS_NAMESPACE} || logFailureAndExit "Unable to apply truststore-mgr worker_role binding"
oc apply -f ${TM_DIR}/worker_service_account.yaml -n ${MAS_NAMESPACE}  || logFailureAndExit "Unable to apply truststore-mgr worker_service account"
oc apply -f ${TMOP_FILE} -n ${MAS_NAMESPACE} || logFailureAndExit "Unable to apply ibm-truststore-mgr operator"

# Cleanup old named ibm-truststore-mgr-operator
oc get deployment ibm-truststore-mgr-operator -n ${MAS_NAMESPACE} > /dev/null 2>&1
if [[ "$?" == "0" ]]; then
  oc delete deployment ibm-truststore-mgr-operator -n ${MAS_NAMESPACE}
fi

# 10. Install (or update) IBM Catalog operator and common services
# -----------------------------------------------------------------------------
echo_h2 "1.1 Installing IBM operator catalog and common services catalog."
oc apply -f ${OC_DIR}/ibm-catalogs.yaml || logFailureAndExit "Unable to apply ibm catalogs(operator catalog and common service catalogs)"


# 11. Install (or update) IBM Maximo Application Suite operator
# -----------------------------------------------------------------------------
echo_h2 "2. Installing ibm-mas operator"
sed -e "s|icr.io/cpopen|${ICR_CPOPEN}|g" \
    -e "s/{{INSTANCE_ID}}/${INSTANCE_ID}/g" \
    $MAS_DIR/ibm-mas-${VERSION}.yaml | oc apply -f - || logFailureAndExit "Unable to apply ibm-mas operator"


# 12. Install (or update) IBM Maximo Application Suite core systems
# -----------------------------------------------------------------------------
echo_h2 "3. Deploying IBM Maximo Application Suite"
oc apply -f ${CR_FILE} -n ${MAS_NAMESPACE} || logFailureAndExit "Unable to deploy IBM Maximo Applicaton Suite"


if [ $? == "0" ]; then
  echo_h2 "4. Waiting for core systems to be ready"
  echo -n "Operator ready              "
  while [[ $(oc get deployment/ibm-mas-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${MAS_NAMESPACE}) != "1" ]];do sleep 5s; done &
  showWorking $!
  printf '\b'
  echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

  echo -n "Superuser account ready     "
  while [[ $(oc get secret/${INSTANCE_ID}-credentials-superuser --ignore-not-found=true -n ${MAS_NAMESPACE} | wc -l) == "0" ]];do sleep 5s; done &
  showWorking $!
  printf '\b'
  echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

  echo -n "Admin dashboard ready       "
  while [[ $(oc get deployment/${INSTANCE_ID}-admin-dashboard --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${MAS_NAMESPACE}) != "1" ]];do sleep 5s; done &
  showWorking $!
  printf '\b'
  echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

  echo -n "Core API ready              "
  while [[ $(oc get deployment/${INSTANCE_ID}-coreapi --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${MAS_NAMESPACE}) != "3" ]];do sleep 5s; done &
  showWorking $!
  printf '\b'
  echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

  echo_h1 "Installation Summary"
  echo_h2 "Administration Dashboard URL"
  echo_highlight "https://admin.${DOMAIN}"

  echo_h2 "Super User Credentials"
  echo -n "Username: "
  oc get secret ${INSTANCE_ID}-credentials-superuser -o jsonpath='{.data.username}' -n ${MAS_NAMESPACE} | base64 --decode && echo ""
  echo -n "Password: "
  oc get secret ${INSTANCE_ID}-credentials-superuser -o jsonpath='{.data.password}' -n ${MAS_NAMESPACE} | base64 --decode && echo ""

  echo -e "\nPlease make a record of the superuser credentials."
  echo ""
  echo "If this is a new installation, you can now complete the initial setup"
  echo "Sign in as the superuser at this URL:"
  echo_highlight "https://admin.${DOMAIN}/initialsetup"
  echo ""

  exit 0
else
  echo -e "${COLOR_RED}Installation Failed${COLOR_RESET}"
  echo ""
  exit 1
fi
