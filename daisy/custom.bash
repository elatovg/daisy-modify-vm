#!/bin/bash
## GLOBALS
if [ -f /etc/debian_version ]; then
  DISTRO='Debian'
elif [ -f /etc/redhat-release ]; then
  DISTRO='Redhat'
fi

## BINS
if [ "${DISTRO}" == "Debian" ]; then
  MKDIR="/bin/mkdir"
  APT="/bin/apt"
  GIT="/bin/git"
  ANSIBLE_PLAYBOOK="/bin/ansible-playbook"
  CURL="/bin/curl"
  CUT="/bin/cut"
  MV="/bin/mv"
  LN="/bin/ln"
  SYSTEMCTL="/bin/systemctl"
fi

## CONFIGS
DATA_DIR="/data"
ANSIBLE_DIR="${DATA_DIR}/ansible-repo"
ANS_ETC_DIR="/etc/ansible"
VM_NAME=$(${CURL} -H Metadata-Flavor:Google \
  http://metadata/computeMetadata/v1/instance/hostname | ${CUT} -d. -f1)
VM_ZONE=$(${CURL} -H Metadata-Flavor:Google \
  http://metadata/computeMetadata/v1/instance/zone | ${CUT} -d/ -f4)

if [ "${DISTRO}" == "Debian" ]; then
  ANSIBLE_PKG="ansible"
  GIT_PKG="git"
fi

function install_pkg() {
  local pkg_name=$1
  if [ "${DISTRO}" == "Debian" ]; then
    ${APT} install "${pkg_name}" -y
  fi

}

function get_ansible() {
  if [ "${DISTRO}" == "Debian" ]; then
    ${APT} update
  fi
  install_pkg ${ANSIBLE_PKG}
  ansible_git_repo=$(${CURL} -H Metadata-Flavor:Google \
    http://metadata.google.internal/computeMetadata/v1/instance/attributes/ansible_git_repo)
  install_pkg ${GIT_PKG}

  if [ ! -d ${DATA_DIR} ]; then
    ${MKDIR} -p ${DATA_DIR}
  else
    echo "${DATA_DIR} already exists"
  fi

  # Clone the ansible git repo
  if [ -d "${ANSIBLE_DIR}/.git" ]; then
    echo "${ANSIBLE_DIR} already exist and has git repo, just pulling"
    ${GIT} -C ${ANSIBLE_DIR} pull
  else
    ${GIT} clone "${ansible_git_repo}" ${ANSIBLE_DIR}
  fi

  # Create metadata to mark ansible repo creation
  #   echo "${ANSIBLE_DIR} cloned successfully, adding metadata"
  #   ${GCLOUD} compute instances add-metadata "${VM_NAME}" \
  #     --zone "${VM_ZONE}" --metadata ansible_repo_ready=true
}

function run_ansible() {
  ${MKDIR} -p ${ANS_ETC_DIR}
  # ${MV} "${ANS_ETC_DIR}/hosts" "${ANS_ETC_DIR}/hosts.bak"
  # ${MV} "${ANS_ETC_DIR}/roles" "${ANS_ETC_DIR}/roles.bak"
  ${LN} -s ${ANSIBLE_DIR}/ansible/roles/ ${ANS_ETC_DIR}/roles
  ${LN} -s ${ANSIBLE_DIR}/ansible/hosts ${ANS_ETC_DIR}/hosts
  # ${ANSIBLE_PLAYBOOK} "${ANSIBLE_DIR}/playbooks/gce.yaml"

  if ! ${ANSIBLE_PLAYBOOK} "${ANSIBLE_DIR}/ansible/playbooks/gce.yaml"; then
    echo "bootstrapped failed"
    return 1
  else
    echo "bootstrapped succeeed"
    # ${GCLOUD} compute instances add-metadata "${VM_NAME}" \
    #   --zone "${VM_ZONE}" --metadata bootstrapped=true
    return 0
  fi
}

${APT} update
${APT} upgrade -y
get_ansible
if ! run_ansible; then
    echo "bootstrapped failed, not powering off for troubleshooting"
    exit 1
else
  echo "bootstrapped succeeded, powering off"
  # poweroff after the bootstrap
  ${SYSTEMCTL} poweroff
fi