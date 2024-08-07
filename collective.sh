#!/bin/sh

# Script version
SCRIPT_VERSION="1.0.0"

# Default settings
BORG_CONFIG_FILE="/root/.borg.settings"
REMOTE_PATH=""
BACKUP_LOCATIONS="/etc /home /root /mount /var"
EXCLUDE_LIST=""
ON_SUCCESS=""
ON_WARNING=""
ON_FAILURE=""

GITHUB_ACCOUNT="disappointingsupernova"
REPO_NAME="collective"
SCRIPT_NAME="collective.sh"
DISPLAY_NAME="Collective"
GITHUB_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/$SCRIPT_NAME"
VERSION_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/VERSION"
GPG_KEY_FINGERPRINT="7D2D35B359A3BB1AE7A2034C0CB5BB0EFE677CA8"

TEMP_DIR=$(mktemp -d)
OUTPUT_FILE="$TEMP_DIR/${REPO_NAME}_pgp_message.txt"

# Function to check if the script is installed in /usr/bin/$REPO_NAME
check_installation() {
    if [ ! -f /usr/bin/$REPO_NAME ]; then
        read -p "Do you want to install $DISPLAY_NAME to /usr/bin/$REPO_NAME? [Y/n]: " response
        response=${response:-yes}
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            echo "Installing $DISPLAY_NAME to /usr/bin/$REPO_NAME..."
            cp "$0" /usr/bin/$REPO_NAME
            chmod +x /usr/bin/$REPO_NAME
            echo "$DISPLAY_NAME installed successfully to /usr/bin/$REPO_NAME."
            echo "Removing script from the current location."
            rm -f "$0"
            exit 0
        else
            echo "Skipping installation to /usr/bin/$REPO_NAME."
        fi
    fi
}

log() {
    echo "$(date) $*" | tee -a $OUTPUT_FILE
}

send_email() {
    SUBJECT=$1
    gpg --sign --encrypt -a -r $GPG_KEY_FINGERPRINT $OUTPUT_FILE
    echo "Subject: $SUBJECT" > "$TEMP_DIR/email.txt"
    cat ${OUTPUT_FILE}.asc >> "$TEMP_DIR/email.txt"
    sendmail -f "borg@$(hostname)" $EMAIL_RECIPIENT < "$TEMP_DIR/email.txt"
    rm ${OUTPUT_FILE}.asc "$TEMP_DIR/email.txt"
}

handle_exit() {
    EXIT_CODE=$1
    if [ $EXIT_CODE -eq 0 ]; then
        log "Backup and Prune finished successfully"
        [ -n "$ON_SUCCESS" ] && eval "$ON_SUCCESS"
        SUBJECT="borg SUCCESS: $(hostname) - $remote_storage_location"
    elif [ $EXIT_CODE -eq 1 ]; then
        log "Backup and Prune finished with warnings"
        [ -n "$ON_WARNING" ] && eval "$ON_WARNING"
        SUBJECT="borg WARNING: $(hostname) - $remote_storage_location"
    else
        log "Backup and Prune finished with errors"
        [ -n "$ON_FAILURE" ] && eval "$ON_FAILURE"
        SUBJECT="borg FAILURE: $(hostname) @ $(date) - $remote_storage_location"
    fi
    send_email "$SUBJECT"
    rm -rf $TEMP_DIR
}

show_help() {
    echo "Usage: $0 [options]
Options:
  -c FILE          Specify the Borg configuration file (default: /root/.borg.settings)
  -l DIRS          Specify the directories to back up as a space-separated list (default: /etc /home /root /mount /var)
  -e EXCLUDES      Specify paths to exclude as a comma-separated list (e.g., 'home/*/.cache/*,var/tmp/*')
  -s CMD           Command to run on successful completion
  -w CMD           Command to run on completion with warnings
  -f CMD           Command to run on failure
  -r, --remote     Specify the remote path for Borg operations
  -u, --update     Update the script to the latest version from GitHub
  -h, --help       Show this help message and exit"
}

install_borg() {
    if [ -f /etc/debian_version ]; then
        echo "Installing BorgBackup on Debian-based system..."
        apt-get update
        apt-get install -y borgbackup
    elif [ -f /etc/redhat-release ]; then
        echo "Installing BorgBackup on RedHat-based system..."
        yum install -y epel-release
        yum install -y borgbackup
    else
        echo "Unsupported OS. Please install BorgBackup manually."
        exit 1
    fi
}

install_sendmail() {
    if [ -f /etc/debian_version ]; then
        echo "Installing sendmail on Debian-based system..."
        apt-get install -y sendmail
    elif [ -f /etc/redhat-release ]; then
        echo "Installing sendmail on RedHat-based system..."
        yum install -y sendmail
    else
        echo "Unsupported OS. Please install sendmail manually."
        exit 1
    fi
}

check_borg_installed() {
    if ! command -v borg > /dev/null; then
        install_borg
    fi
}

check_sendmail_installed() {
    if ! command -v sendmail > /dev/null; then
        install_sendmail
    fi
}

check_gpg_key_installed() {
    if ! gpg --list-keys $GPG_KEY_FINGERPRINT > /dev/null 2>&1; then
        echo "GPG key with fingerprint $GPG_KEY_FINGERPRINT not found. Importing from keyserver.ubuntu.com..."
        gpg --keyserver keyserver.ubuntu.com --recv-keys $GPG_KEY_FINGERPRINT
    fi
}

generate_passphrase() {
    openssl rand -base64 96 | tr -d '\n'
}

prompt_for_config() {
    echo "Borg configuration file not found. Let's create it."
    read -p "Enter the remote username: " USERNAME
    read -p "Enter the remote server address (default: borg.sarik.tech): " remote_server_address
    remote_server_address=${remote_server_address:-borg.sarik.tech}
    read -p "Enter the remote SSH port (default: 22): " remote_ssh_port
    remote_ssh_port=${remote_ssh_port:-22}
    read -p "Enter the remote SSH key path (default: /root/.ssh/borg): " remote_ssh_key
    remote_ssh_key=${remote_ssh_key:-/root/.ssh/borg}
    read -s -p "Enter a secure BORG_PASSPHRASE (leave empty to generate one): " BORG_PASSPHRASE
    echo

    if [ -z "$BORG_PASSPHRASE" ]; then
        BORG_PASSPHRASE=$(generate_passphrase)
        echo "Generated secure BORG_PASSPHRASE: $BORG_PASSPHRASE"
    fi

    email_address="$(hostname)@sarik.tech"

cat <<EOF > $BORG_CONFIG_FILE
remote_ssh_port="$remote_ssh_port"
remote_ssh_key="$remote_ssh_key"
email_address="$email_address"
USERNAME="$USERNAME"
remote_server_address="$remote_server_address"
remote_storage_location="\$USERNAME@\$remote_server_address:\$remote_ssh_port/mount/\$USERNAME/borg"

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=ssh://\$remote_storage_location
export BORG_RSH="ssh -4 -i \$remote_ssh_key"
export BORG_PASSPHRASE='$BORG_PASSPHRASE'
EOF

    echo "Borg configuration file created at $BORG_CONFIG_FILE"
}

initialize_borg_repo() {
    if ! borg info > /dev/null 2>&1; then
        echo "Borg repository not initialized. Initializing now."
        borg init -e repokey
        borg key export :: | tee >(cat >&2)
    fi
}

update_script() {
    echo "Checking for updates..."
    LATEST_VERSION=$(curl -sSL $VERSION_URL)
    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        echo "Updating script from $GITHUB_URL..."
        curl -o "$0" -sSL "$GITHUB_URL" && chmod +x "$0"
        echo "Script updated to version $LATEST_VERSION."
        exit 0
    else
        echo "You are already using the latest version ($SCRIPT_VERSION)."
        exit 0
    fi
}

trap 'log "Backup interrupted"; exit 2' INT TERM

# Check installation
check_installation

# Parse command-line arguments
while getopts ":c:l:e:s:w:f:r:uh-:" opt; do
  case ${opt} in
    c )
      BORG_CONFIG_FILE=$OPTARG
      ;;
    l )
      BACKUP_LOCATIONS=$OPTARG
      ;;
    e )
      EXCLUDE_LIST=$OPTARG
      ;;
    s )
      ON_SUCCESS=$OPTARG
      ;;
    w )
      ON_WARNING=$OPTARG
      ;;
    f )
      ON_FAILURE=$OPTARG
      ;;
    r )
      REMOTE_PATH=$OPTARG
      ;;
    u )
      update_script
      ;;
    h )
      show_help
      exit 0
      ;;
    - )
      case "${OPTARG}" in
        help)
          show_help
          exit 0
          ;;
        update)
          update_script
          ;;
        remote)
          REMOTE_PATH="$2"
          shift
          ;;
        *)
          echo "Invalid option: --${OPTARG}" 1>&2
          show_help
          exit 1
          ;;
      esac
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      show_help
      exit 1
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      show_help
      exit 1
      ;;
  esac
done

check_borg_installed
check_sendmail_installed
check_gpg_key_installed

if [ ! -f "$BORG_CONFIG_FILE" ]; then
    prompt_for_config
fi

. $BORG_CONFIG_FILE

initialize_borg_repo

log "Starting Backup with locations: $BACKUP_LOCATIONS"

# Prepare exclude options
IFS=',' read -ra EXCLUDES <<< "$EXCLUDE_LIST"
EXCLUDE_OPTS=""
for EXCLUDE in "${EXCLUDES[@]}"; do
    EXCLUDE_OPTS+="--exclude $EXCLUDE "
done

# Prepare remote path option
REMOTE_OPTS=""
if [ -n "$REMOTE_PATH" ]; then
    REMOTE_OPTS="--remote-path=$REMOTE_PATH"
fi

# Backup
borg create --verbose --filter AME --list --stats --show-rc --compression lz4 \
    --exclude-caches $EXCLUDE_OPTS $REMOTE_OPTS \
    ::'{hostname}-{now}' $BACKUP_LOCATIONS 2>&1 | tee -a $OUTPUT_FILE

backup_exit=${PIPESTATUS[0]}

log "Pruning Repository"

# Prune
borg prune --list --glob-archives '{hostname}-*' --show-rc --keep-within 14d \
    --keep-daily 28 --keep-weekly 8 --keep-monthly 48 $REMOTE_OPTS 2>&1 | tee -a $OUTPUT_FILE

prune_exit=${PIPESTATUS[0]}
compact_exit=0  # Assuming compact command or similar would go here

# Determine global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

handle_exit $global_exit

# Cleanup
rm -rf $TEMP_DIR

exit $global_exit
