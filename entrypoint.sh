#!/bin/bash

###############################################################################

# Set environment variables
SCRIPT_NAME=$(basename $0)
CEPH_ADDRESS=""
CEPH_HOSTNAME=""
CEPH_FORCE=""
CEPH_PREFIX="/ceph"
CEPH_SAMPLE_CONFIG="/usr/share/ceph/ceph.conf"
CEPH_CLUSTER_NAME="ceph"
CEPH_CLUSTER_UUID=""
CEPH_PATH_ETC=""
CEPH_PATH_VAR=""
CEPH_DEVICE_TYPE="raw"

# Names of the configuration files
CEPH_FILE_CONFIG="ceph.conf"
CEPH_FILE_KEYRING_CLIENT="client.keyring"
CEPH_FILE_KEYRING_MONITOR="mon.keyring"
CEPH_FILE_KEYRING_MANAGER="mgr.keyring"
CEPH_FILE_MONITOR_MAP="monmap"

# Names of the keyrings
CEPH_KEY_CLIENT_ADMIN="client.admin"

###############################################################################

usage() { 
    echo
    echo "Usage:"
    echo " ${SCRIPT_NAME} --help"
    echo "   Print this help message"
    echo
    echo " ${SCRIPT_NAME} -f|--force -a|--address <mon-address> -h|--hostname <mon-hostname> -c|--cluster <name> bootstrap-mon"
    echo "   Create credentials and monitor server with the given address"
    echo "   use the force flag in order to overwrite existing credentials" 
    echo
    echo " ${SCRIPT_NAME} -f|--force create-client-admin-keyring"
    echo "   Create initial client admin keyring. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -f|--force -h|--hostname <mon-hostname> create-monitor-keyring"
    echo "   Create monitor keyring. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -f|--force -h|--hostname <mon-hostname> create-manager-keyring"
    echo "   Create manager keyring. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -f|--force -a|--address <mon-address> -h|--hostname <mon-hostname> create-monitor-map"
    echo "   Create monitor map. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -f|--force -h|--hostname <mon-hostname> -c|--cluster <name> create-monitor-path"
    echo "   Create monitor path for files. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -f|--force -h|--hostname <mon-hostname> -c|--cluster <name> create-manager-path"
    echo "   Create manager path for files. Force re-creation if the force flag is set"
    echo
    echo " ${SCRIPT_NAME} -h|--hostname <mon-hostname> monitor"
    echo "   Run previously bootstrapped monitor"
    echo
    echo " ${SCRIPT_NAME} -h|--hostname <mon-hostname> manager"
    echo "   Run previously bootstrapped manager"
    echo
    echo " ${SCRIPT_NAME} -t|--type <lvm|raw> -c|--cluster <name> create-block-device <path>"
    echo "   Create block device"
    echo
    exit 1;
}

###############################################################################

init-vars() {
    # Check prefix
    if [ -z "${CEPH_PREFIX}" ]; then
        echo "Missing --prefix"
        exit 1
    fi

    # Set etc and var paths
    CEPH_PATH_ETC="${CEPH_PREFIX}/etc"
    CEPH_PATH_VAR="${CEPH_PREFIX}/var"
    CEPH_PATH_LOG="${CEPH_PREFIX}/log"

    # Check for etc and var, create as needed
    if [ ! -d "${CEPH_PATH_ETC}" ]; then
        echo "Creating ${CEPH_PATH_ETC}"
        install -d -m 0755 "${CEPH_PATH_ETC}" || exit 1
    fi
    if [ ! -d "${CEPH_PATH_VAR}" ]; then
        echo "Creating ${CEPH_PATH_VAR}"
        install -d -m 0755 "${CEPH_PATH_VAR}" || exit 1
    fi
    if [ ! -d "${CEPH_PATH_LOG}" ]; then
        echo "Creating ${CEPH_PATH_LOG}"
        install -d -m 0755 -o ceph -g ceph "${CEPH_PATH_LOG}" || exit 1
    fi

    # Paths to files
    CEPH_KEYRING_CLIENT="${CEPH_PATH_ETC}/${CEPH_FILE_KEYRING_CLIENT}"
    CEPH_KEYRING_MONITOR="${CEPH_PATH_ETC}/${CEPH_FILE_KEYRING_MONITOR}"
    CEPH_KEYRING_MANAGER="${CEPH_PATH_ETC}/${CEPH_FILE_KEYRING_MANAGER}"
    CEPH_MONITOR_MAP="${CEPH_PATH_ETC}/${CEPH_FILE_MONITOR_MAP}"
    CEPH_CONFIG="${CEPH_PATH_ETC}/${CEPH_FILE_CONFIG}"

    # Paths to binaries
    CEPH_AUTHTOOL_BIN="/usr/bin/ceph-authtool"
    CEPH_MONTOOL_BIN="/usr/bin/ceph-mon"
    CEPH_MGRTOOL_BIN="/usr/bin/ceph-mgr"
    CEPH_VOLUMETOOL_BIN=$(which ceph-volume)
    CEPH_MONMAP_BIN="/usr/bin/monmaptool"
    if [ ! -x "${CEPH_AUTHTOOL_BIN}" ]; then
        echo "Missing ${CEPH_AUTHTOOL_BIN}"
        exit 1
    fi
    if [ ! -x "${CEPH_MONMAP_BIN}" ]; then
        echo "Missing ${CEPH_MONMAP_BIN}"
        exit 1
    fi
    if [ ! -x "${CEPH_MONTOOL_BIN}" ]; then
        echo "Missing ${CEPH_MONTOOL_BIN}"
        exit 1
    fi
    if [ ! -x "${CEPH_MGRTOOL_BIN}" ]; then
        echo "Missing ${CEPH_MGRTOOL_BIN}"
        exit 1
    fi
    if [ ! -x "${CEPH_VOLUMETOOL_BIN}" ]; then
        echo "Missing ${CEPH_VOLUMETOOL_BIN}"
        exit 1
    fi

    # Retrieve the cluster uuid
    if [ -f "${CEPH_CONFIG}" ]; then
        CEPH_CLUSTER_UUID=$(grep "fsid" "${CEPH_CONFIG}" | awk '{print $3}')
    fi

    # Set monitor and manager path
    CEPH_MONITOR_PATH="${CEPH_PATH_VAR}/mon/${CEPH_CLUSTER_NAME}-${CEPH_HOSTNAME}"
    CEPH_MANAGER_PATH="${CEPH_PATH_VAR}/mgr/${CEPH_CLUSTER_NAME}-${CEPH_HOSTNAME}"
}

###############################################################################

bootstrap-mon() { 
    # Check address parameter
    if [ -z "${CEPH_ADDRESS}" ]; then
        echo "Missing --address"
        exit 1
    fi

    # Verbose logging
    echo
    echo "bootstrap-mon"
    echo "  address: ${CEPH_ADDRESS}"
    echo "  etc: ${CEPH_PATH_ETC}"
    echo "  var: ${CEPH_PATH_VAR}"
    echo "  config: ${CEPH_CONFIG}"
    echo

    # Check for existing credentials, or create if force is set
    if [ ! -f "${CEPH_SAMPLE_CONFIG}" ]; then
        echo "Missing ${CEPH_SAMPLE_CONFIG}"
        exit 1
    fi
    if [ ! -f "${CEPH_CONFIG}" ] || [ ! -z "${CEPH_FORCE}" ]; then
        echo "Creating configuration file"
        CEPH_CLUSTER_UUID=$(uuidgen)
        cp "${CEPH_SAMPLE_CONFIG}" "${CEPH_CONFIG}" | exit 1
        sed -i "s/{cluster-id}/${CEPH_CLUSTER_UUID}/g" "${CEPH_CONFIG}" | exit 1
        sed -i "s/{ip-address}/${CEPH_ADDRESS}/g" "${CEPH_CONFIG}" | exit 1
        chmod 0644 "${CEPH_CONFIG}" | exit 1
    else 
        echo "  => configuration file already exists, not changing. Use --force to create a new one"
    fi

    # Create the client and monitor keyrings, monitor map
    create-client-admin-keyring || exit 1
    create-monitor-keyring || exit 1
    create-manager-keyring || exit 1
    create-monitor-map || exit 1
    create-monitor-path || exit 1
    create-manager-path || exit 1
    create-monitor-config || exit 1

    # Return success
    echo
}

###############################################################################

create-client-admin-keyring() {
    CEPH_KEY_NAME="${CEPH_KEY_CLIENT_ADMIN}"

    # Verbose logging
    echo
    echo "create-client-admin-keyring"
    echo "  keyring: ${CEPH_KEYRING_CLIENT}"
    echo "  key: ${CEPH_KEY_NAME}"
    echo

    if [ ! -f "${CEPH_KEYRING_CLIENT}" ] || [ ! -z "${CEPH_FORCE}" ]; then
        ${CEPH_AUTHTOOL_BIN} ${CEPH_KEYRING_CLIENT} --create-keyring --gen-key -n "${CEPH_KEY_NAME}" \
          --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *' || exit 1
    else 
        echo "  => client key already exists, not changing. Use --force to create a new one"
    fi

    # Return success
    echo
}

###############################################################################

create-monitor-keyring() {
    CEPH_KEY_NAME="mon.${CEPH_HOSTNAME}"

    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-monitor-keyring"
    echo "  keyring: ${CEPH_KEYRING_MONITOR}"
    echo "  key: ${CEPH_KEY_NAME}"
    echo

    if [ ! -f "${CEPH_KEYRING_MONITOR}" ] || [ ! -z "${CEPH_FORCE}" ]; then
        ${CEPH_AUTHTOOL_BIN} ${CEPH_KEYRING_MONITOR} --create-keyring --gen-key -n "${CEPH_KEY_NAME}" || exit 1
    else 
        echo "  => monitor key already exists, not changing. Use --force to create a new one"
    fi

    # Import client admin key
    import-client-admin-keyring "${CEPH_KEYRING_MONITOR}" "${CEPH_KEYRING_CLIENT}" "${CEPH_KEY_CLIENT_ADMIN}" || exit 1

    # Return success
    echo
}

###############################################################################

create-manager-keyring() {
    CEPH_KEY_NAME="mgr.${CEPH_HOSTNAME}"

    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-manager-keyring"
    echo "  keyring: ${CEPH_KEYRING_MANAGER}"
    echo "  key: ${CEPH_KEY_NAME}"
    echo

    if [ ! -f "${CEPH_KEYRING_MANAGER}" ] || [ ! -z "${CEPH_FORCE}" ]; then
        ${CEPH_AUTHTOOL_BIN} ${CEPH_KEYRING_MANAGER} --create-keyring --gen-key -n "${CEPH_KEY_NAME}"  \
          --cap mon 'allow profile mgr' --cap osd 'allow *' --cap mds 'allow *' || exit 1
    else 
        echo "  => manager key already exists, not changing. Use --force to create a new one"
    fi

    # Import client admin key
    if [ -f "${CEPH_KEYRING_MANAGER}" ]; then
        import-client-admin-keyring "${CEPH_KEYRING_MONITOR}" "${CEPH_KEYRING_MANAGER}" "${CEPH_KEY_NAME}" || exit 1
    fi

    # Return success
    echo
}

###############################################################################

create-osd-keyring() {
    CEPH_KEY_NAME="client.bootstrap-osd"

    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-monitor-keyring"
    echo "  keyring: ${CEPH_KEYRING_MONITOR}"
    echo "  key: ${CEPH_KEY_NAME}"
    echo

    if [ ! -f "${CEPH_KEYRING_MONITOR}" ] || [ ! -z "${CEPH_FORCE}" ]; then
        ${CEPH_AUTHTOOL_BIN} ${CEPH_KEYRING_MONITOR} --create-keyring --gen-key -n "${CEPH_KEY_NAME}" || exit 1
    else 
        echo "  => monitor key already exists, not changing. Use --force to create a new one"
    fi

    # Import client admin key
    import-client-admin-keyring "${CEPH_KEYRING_MONITOR}" "${CEPH_KEYRING_CLIENT}" "${CEPH_KEY_CLIENT_ADMIN}" || exit 1

    # Check the owner and permissions on the keyring
    chown ceph:ceph "${CEPH_KEYRING_MONITOR}" || exit 1
    chmod 660 "${CEPH_KEYRING_MONITOR}" || exit 1

    # Return success
    echo
}

###############################################################################

import-client-admin-keyring() {
    CEPH_DEST_KEYRING=$1
    CEPH_SOURCE_KEYRING=$2
    CEPH_KEY_NAME=$3

    # Verbose logging
    echo
    echo "import-client-admin-keyring"
    echo "  from: ${CEPH_SOURCE_KEYRING}"
    echo "    to: ${CEPH_DEST_KEYRING}"
    echo "   key: ${CEPH_KEY_NAME}"
    echo

    # Check parameters
    if [ ! -f "${CEPH_SOURCE_KEYRING}" ]; then
        echo "  => source keyring does not exist"
        exit 1
    fi
    if [ ! -f "${CEPH_DEST_KEYRING}" ]; then
        echo "  => destination keyring does not exist"
        exit 1
    fi
    if [ -z "${CEPH_KEY_NAME}" ]; then
        echo "  => key name is empty"
        exit 1
    fi

    ${CEPH_AUTHTOOL_BIN} "${CEPH_DEST_KEYRING}" --import-keyring "${CEPH_SOURCE_KEYRING}" -n "${CEPH_KEY_NAME}" || exit 1

    # Return success
    echo
}

###############################################################################

create-monitor-map() {
    # Check parameters
    if [ -z "${CEPH_ADDRESS}" ]; then
        echo "Missing --address"
        exit 1
    fi
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ -z "${CEPH_CLUSTER_UUID}" ]; then
        echo "Missing CEPH_CLUSTER_UUID"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-monitor-map"
    echo "  fsid: ${CEPH_CLUSTER_UUID}"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  address: ${CEPH_ADDRESS}"
    echo "  monmap: ${CEPH_MONITOR_MAP}"
    echo

    if [ ! -f "${CEPH_MONITOR_MAP}" ] || [ ! -z "${CEPH_FORCE}" ]; then
      ${CEPH_MONMAP_BIN} --create --clobber --fsid "${CEPH_CLUSTER_UUID}" \
        --add "${CEPH_HOSTNAME}" "${CEPH_ADDRESS}" "${CEPH_MONITOR_MAP}" || exit 1
    else 
        echo "  => monitor map already exists, not changing. Use --force to create a new one"
    fi

    # Return success
    echo  
}

###############################################################################

create-monitor-path() {
    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ -z "${CEPH_CLUSTER_NAME}" ]; then
        echo "Missing --cluster"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-monitor-path"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  cluster: ${CEPH_CLUSTER_NAME}"
    echo "  path: ${CEPH_MONITOR_PATH}"
    echo

    # Remove existing if forced
    if [ ! -z "${CEPH_FORCE}" ] && [ -d "${CEPH_MONITOR_PATH}" ]; then
        rm -rf "${CEPH_MONITOR_PATH}" || exit 1
    fi

    # Create the monitor path
    if [ ! -d "${CEPH_MONITOR_PATH}" ]; then
        mkdir -p "${CEPH_MONITOR_PATH}" || exit 1
        chown ceph:ceph "${CEPH_MONITOR_PATH}" || exit 1
        chmod 775 "${CEPH_MONITOR_PATH}" || exit 1
    else 
        echo "  => monitor path already exists, not changing. Use --force to create a new one"
    fi

    # Return success
    echo
}


###############################################################################

create-manager-path() {
    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ -z "${CEPH_CLUSTER_NAME}" ]; then
        echo "Missing --cluster"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-manager-path"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  cluster: ${CEPH_CLUSTER_NAME}"
    echo "  path: ${CEPH_MANAGER_PATH}"
    echo

    # Remove existing if forced
    if [ ! -z "${CEPH_FORCE}" ] && [ -d "${CEPH_MANAGER_PATH}" ]; then
        rm -rf "${CEPH_MANAGER_PATH}" || exit 1
    fi

    # Create the manager path
    if [ ! -d "${CEPH_MANAGER_PATH}" ]; then
        mkdir -p "${CEPH_MANAGER_PATH}" || exit 1
        chown ceph:ceph "${CEPH_MANAGER_PATH}" || exit 1
        chmod 775 "${CEPH_MANAGER_PATH}" || exit 1
    else 
        echo "  => manger path already exists, not changing. Use --force to create a new one"
    fi

    # Return success
    echo
}


###############################################################################

create-monitor-config() {
    # Check parameters
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ -z "${CEPH_CLUSTER_NAME}" ]; then
        echo "Missing --cluster"
        exit 1
    fi
    if [ ! -f "${CEPH_CONFIG}" ] ; then
        echo "Missing confguration file"
    fi
    if [ ! -f "${CEPH_KEYRING_MONITOR}" ] ; then
        echo "Missing monitor keyring file"
    fi
    if [ ! -f "${CEPH_MONITOR_MAP}" ] ; then
        echo "Missing monitor map file"
    fi

    # Verbose logging
    echo
    echo "create-monitor-config"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  cluster: ${CEPH_CLUSTER_NAME}"
    echo "  keyring: ${CEPH_KEYRING_MONITOR}"
    echo "  monmap: ${CEPH_MONITOR_MAP}"
    echo "  config: ${CEPH_CONFIG}"
    echo

    # Create the monitor config
    sudo -u ceph ${CEPH_MONTOOL_BIN} --mkfs -c "${CEPH_CONFIG}" -i "${CEPH_HOSTNAME}" --monmap "${CEPH_MONITOR_MAP}" --keyring "${CEPH_KEYRING_MONITOR}" || exit 1
}

###############################################################################

run-monitor() {
    # Check parameters
    if [ ! -f "${CEPH_CONFIG}" ] ; then
        echo "Missing confguration file"
    fi
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ ! -f "${CEPH_KEYRING_MONITOR}" ] ; then
        echo "Missing monitor keyring file"
    fi

    # Verbose logging
    echo
    echo "run-monitor"
    echo "  config: ${CEPH_CONFIG}"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  keyring: ${CEPH_KEYRING_MONITOR}"
    echo "  path: ${CEPH_MONITOR_PATH}"

    # Copy keyring file over to monitor path, make readable by ceph
    install -m 644 -o ceph -g ceph "${CEPH_KEYRING_MONITOR}" "${CEPH_MONITOR_PATH}/keyring" || exit 1

    # Run monitor
    ${CEPH_MONTOOL_BIN} \
      -c "${CEPH_CONFIG}" -i "${CEPH_HOSTNAME}" \
      --setuser ceph --setgroup ceph \
      --log-to-file=false --mon_cluster_log_to_file=false \
      -d || exit 1
}


###############################################################################

run-manager() {
    # Check parameters
    if [ ! -f "${CEPH_CONFIG}" ] ; then
        echo "Missing confguration file"
    fi
    if [ -z "${CEPH_HOSTNAME}" ]; then
        echo "Missing --hostname"
        exit 1
    fi
    if [ ! -f "${CEPH_KEYRING_MANAGER}" ] ; then
        echo "Missing manager keyring file"
    fi

    # Verbose logging
    echo
    echo "run-manager"
    echo "  config: ${CEPH_CONFIG}"
    echo "  hostname: ${CEPH_HOSTNAME}"
    echo "  keyring: ${CEPH_KEYRING_MONITOR}"
    echo "  path: ${CEPH_MONITOR_PATH}"

    # Copy keyring file over to monitor path, makr readable by ceph
    install -m 644 -o ceph -g ceph "${CEPH_KEYRING_MANAGER}" "${CEPH_MANAGER_PATH}/keyring" || exit 1

    # Run manager
    ${CEPH_MGRTOOL_BIN} \
      -c "${CEPH_CONFIG}" -i "${CEPH_HOSTNAME}" \
      --setuser ceph --setgroup ceph \
      -d || exit 1
}

###############################################################################

create-block-device() {
    CEPH_PATH_DEVICE=$1

    # Check parameters
    if [ ! -b "${CEPH_PATH_DEVICE}" ] ; then
        echo "Missing device"
        exit 1
    fi
    if [ -z "${CEPH_CLUSTER_NAME}" ]; then
        echo "Missing --cluster"
        exit 1
    fi
    if [ -z "${CEPH_DEVICE_TYPE}" ]; then
        echo "Missing --type"
        exit 1
    fi

    # Verbose logging
    echo
    echo "create-block-device"
    echo "  device: ${CEPH_PATH_DEVICE}"
    echo "  type: ${CEPH_DEVICE_TYPE}"
    echo "  cluster: ${CEPH_CLUSTER_NAME}"

    # Create the block device
    case "${CEPH_DEVICE_TYPE}" in
    raw)
        ${CEPH_VOLUMETOOL_BIN} --log-path "${CEPH_PATH_LOG}/${CEPH_CLUSTER_NAME}.log" --cluster "${CEPH_CLUSTER_NAME}" \
          raw prepare \
          --bluestore --data "${CEPH_PATH_DEVICE}" || exit 1
        ;;
     *)
       echo "Unsupported device type: ${CEPH_DEVICE_TYPE}"
       ;;
    esac
}


###############################################################################

OPTIONS=$(getopt --options "pfa:h:c:t:" --longoptions "help,prefix,force,address:,hostname:,cluster:,type:" --name "${SCRIPT_NAME}" -- "$@")
eval set --${OPTIONS}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      ;;
    -f | --force)
      CEPH_FORCE=1
      shift
      ;;
    -a | --address)
      CEPH_ADDRESS="$2"
      shift 2
      ;;
    -h | --hostname)
      CEPH_HOSTNAME="$2"
      shift 2
      ;;
    -c | --cluster)
      CEPH_CLUSTER_NAME="$2"
      shift 2
      ;;
    -t | --type)
      CEPH_DEVICE_TYPE="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      ;;      
  esac
done

shift $((OPTIND-1))

# Check for required arguments
if [ "${#}" == 0 ]; then
  usage
fi

###############################################################################

case "$1" in
  bootstrap-mon)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      bootstrap-mon
    fi
    ;;
  create-client-admin-keyring)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-client-admin-keyring
    fi
    ;;
  create-monitor-keyring)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-monitor-keyring   
    fi
    ;; 
  create-manager-keyring)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-manager-keyring   
    fi
    ;; 
  create-monitor-map)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-monitor-map   
    fi
    ;; 
  create-monitor-path)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-monitor-path
    fi
    ;; 
  create-manager-path)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      create-manager-path
    fi
    ;; 
  monitor)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      run-monitor
    fi
    ;; 
  manager)
    init-vars
    if [ "${#}" != 1 ]; then
      usage
    else 
      run-manager
    fi
    ;; 
  create-block-device)
    init-vars
    if [ "${#}" != 2 ]; then
      usage
    else 
      create-block-device "$2"
    fi
    ;;
  *)
    usage
    ;;      
esac
