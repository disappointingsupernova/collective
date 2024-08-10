#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
GITHUB_ACCOUNT="disappointingsupernova"
REPO_NAME="collective"
SCRIPT_NAME="collective.sh"
DISPLAY_NAME="Collective"
GITHUB_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/$SCRIPT_NAME"
VERSION_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/VERSION"


# Function to find the full path of a command
function find_command() {
    local cmd="$1"
    local path
    path=$(which "$cmd")
    if [ -z "$path" ]; then
        log "Error: $cmd not found. Please ensure it is installed and available in your PATH."
        exit 1
    fi
    echo "$path"
}

SENDMAIL_CMD=$(find_command sendmail)
GPG_CMD=$(find_command gpg)
CURL_CMD=$(find_command curl)
BORG_CMD=$(find_command borg)
TEE_CMD=$(find_command tee)
LOGGER_CMD=$(find_command logger)

TEMP_DIR=$(mktemp -d) || { echo "Failed to create temporary directory"; exit 1; }
OUTPUT_FILE="$TEMP_DIR/${REPO_NAME}_pgp_message.txt"

log() {
    local message="$(date) $*"
    echo "$message" | $TEE_CMD -a $OUTPUT_FILE
    echo "$message" | $LOGGER_CMD -t "$DISPLAY_NAME"
}

log "GitHub settings initialized."

log "All necessary commands have been located."

log "Temporary directory created: $TEMP_DIR"
log "Logging initalized"

# Change to a safe directory
cd /tmp || { echo "Failed to change directory to /tmp"; exit 1; }
log "Changed to /tmp directory."

# Script version
SCRIPT_VERSION="1.0.13"
log "Script version: $SCRIPT_VERSION"

EMAIL_RECIPIENT="$(hostname)@sarik.tech"
log "Email recipient set to $EMAIL_RECIPIENT"

# Default settings
BORG_CONFIG_FILE="/root/.borg.settings"
REMOTE_PATH=""
DEFAULT_BACKUP_LOCATIONS="/etc /home /root /var"
DEFAULT_EXCLUDE_LIST="home/*/.cache/*,var/tmp/* "
ON_SUCCESS=""
ON_WARNING=""
ON_FAILURE=""
DEFAULT_KEEP_WITHIN="14d"
DEFAULT_KEEP_DAILY="28"
DEFAULT_KEEP_WEEKLY="8"
DEFAULT_KEEP_MONTHLY="48"
GPG_KEY_FINGERPRINT="7D2D35B359A3BB1AE7A2034C0CB5BB0EFE677CA8"
log "Default settings initialized."

# Function to find the full path of a command
function find_command() {
    local cmd="$1"
    local path
    path=$(which "$cmd")
    if [ -z "$path" ]; then
        log "Error: $cmd not found. Please ensure it is installed and available in your PATH."
        exit 1
    fi
    echo "$path"
}

# Function to check if the script is installed in /usr/bin/$REPO_NAME
check_installation() {
    if [ ! -f /usr/bin/$REPO_NAME ]; then
        read -p "Do you want to install $DISPLAY_NAME to /usr/bin/$REPO_NAME? [Y/n]: " response
        response=${response:-yes}
        if [ "$response" = "y" ] || [ "$response" = "Y" ] || [ "$response" = "yes" ] || [ "$response" = "Yes" ]; then
            log "Installing $DISPLAY_NAME to /usr/bin/$REPO_NAME..."
            cp "$0" /usr/bin/$REPO_NAME
            chmod +x /usr/bin/$REPO_NAME
            log "$DISPLAY_NAME installed successfully to /usr/bin/$REPO_NAME."
            log "Removing script from the current location."
            rm -f "$0"
            exit 0
        else
            log "Skipping installation to /usr/bin/$REPO_NAME."
        fi
    fi
}

send_email() {
    if ! $GPG_CMD --sign --encrypt -a -r $GPG_KEY_FINGERPRINT $OUTPUT_FILE; then
        log "Failed to sign and encrypt email."
        return 1
    fi

    if ! {
        echo "From: borg@$(hostname)"
        echo "To: $EMAIL_RECIPIENT"
        echo "Subject: $SUBJECT"
        echo "MIME-Version: 1.0"
        echo "Content-Type: multipart/mixed; boundary=\"COLLECTIVE-BOUNDARY\""
        echo
        echo "--COLLECTIVE-BOUNDARY"
        echo "Content-Type: text/plain"
        echo
        cat "$OUTPUT_FILE.asc"
        echo
        echo "--COLLECTIVE-BOUNDARY--"
    } | $SENDMAIL_CMD -t; then
        log "Failed to send email."
        return 1
    fi

    log "Email sent successfully to $EMAIL_RECIPIENT."
}

handle_exit() {
    EXIT_CODE=$1
    if [ $EXIT_CODE -eq 0 ]; then
        log "Backup and Prune finished successfully"
        [ -n "$ON_SUCCESS" ] && eval "$ON_SUCCESS"
        SUBJECT="borg SUCCESS: $(hostname) - $DISPLAY_NAME"
    elif [ $EXIT_CODE -eq 1 ]; then
        log "Backup and Prune finished with warnings"
        [ -n "$ON_WARNING" ] && eval "$ON_WARNING"
        SUBJECT="borg WARNING: $(hostname) - $remote_storage_location - $DISPLAY_NAME"
    else
        log "Backup and Prune finished with errors"
        [ -n "$ON_FAILURE" ] && eval "$ON_FAILURE"
        SUBJECT="borg FAILURE: $(hostname) @ $(date) - $remote_storage_location - $DISPLAY_NAME"
    fi
    send_email "$SUBJECT"
    rm -rf $TEMP_DIR
    log "Cleaned up temporary files."
}

show_help() {
    echo "Usage: $0 [options]
    
Collective is a backup script that uses BorgBackup to create and manage backups.
It includes features such as email notifications, GPG encryption, and remote path configuration.
You can also update the script to the latest version from GitHub.

Options:
  -c FILE          Specify the Borg configuration file (default: /root/.borg.settings)
                   Example: -c /path/to/config.file
  -l DIRS          Specify the directories to back up as a space-separated list (default: /etc /home /root /var)
                   Example: -l '/etc /var/www /opt'
  -e EXCLUDES      Specify paths to exclude as a comma-separated list
                   Example: -e '/mount/storage/ncc1701d,/mount/ncc1701d'
  -s CMD           Command to run on successful completion
                   Example: -s 'echo Success'
  -w CMD           Command to run on completion with warnings
                   Example: -w 'echo Warning'
  -f CMD           Command to run on failure
                   Example: -f 'echo Failure'
  -r, --remote     Specify the remote path for Borg operations
                   Example: -r /remote/path
  -u, --update     Update the script to the latest version from GitHub
  -u, --update=force   Force update the script to the latest version from GitHub even if the current version is the latest
  -v, --version    Show the script version and exit
  -h, --help       Show this help message and exit
  --keep-within    Specify the time interval to keep backups (default: 14d)
                   Example: --keep-within 7d
  --keep-daily     Specify the number of daily backups to keep (default: 28)
                   Example: --keep-daily 14
  --keep-weekly    Specify the number of weekly backups to keep (default: 8)
                   Example: --keep-weekly 4
  --keep-monthly   Specify the number of monthly backups to keep (default: 48)
                   Example: --keep-monthly 12"
}

show_version() {
    echo "$DISPLAY_NAME version $SCRIPT_VERSION"
}

install_borg() {
    if [ -f /etc/debian_version ]; then
        log "Installing BorgBackup on Debian-based system..."
        apt-get update && apt-get install -y borgbackup || { log "Failed to install BorgBackup on Debian-based system."; exit 1; }
    elif [ -f /etc/redhat-release ]; then
        log "Installing BorgBackup on RedHat-based system..."
        yum install -y epel-release && yum install -y borgbackup || { log "Failed to install BorgBackup on RedHat-based system."; exit 1; }
    else
        log "Unsupported OS. Please install BorgBackup manually."
        exit 1
    fi
    log "BorgBackup installed successfully."
}

install_sendmail() {
    if [ -f /etc/debian_version ]; then
        log "Installing sendmail on Debian-based system..."
        apt-get install -y sendmail || { log "Failed to install sendmail on Debian-based system."; exit 1; }
    elif [ -f /etc/redhat-release ]; then
        log "Installing sendmail on RedHat-based system..."
        yum install -y sendmail || { log "Failed to install sendmail on RedHat-based system."; exit 1; }
    else
        log "Unsupported OS. Please install sendmail manually."
        exit 1
    fi
    log "sendmail installed successfully."
}

check_borg_installed() {
    if ! $BORG_CMD > /dev/null; then
        log "BorgBackup not found. Installing..."
        install_borg
    else
        log "BorgBackup is already installed."
    fi
}

check_sendmail_installed() {
    log "sendmail check function invoked"
    if ! command -v sendmail > /dev/null; then
        log "sendmail not found. Installing..."
        install_sendmail
    else
        log "sendmail is already installed."
    fi
}

check_gpg_key_installed() {
    if ! $GPG_CMD --list-keys $GPG_KEY_FINGERPRINT > /dev/null 2>&1; then
        log "GPG key with fingerprint $GPG_KEY_FINGERPRINT not found. Importing..."
        if ! $GPG_CMD --keyserver keyserver.ubuntu.com --recv-keys $GPG_KEY_FINGERPRINT; then
            log "Failed to import GPG key."
            exit 1
        fi
    fi
    log "GPG key is installed."
}

generate_passphrase() {
    openssl rand -base64 96 | tr -d '\n'
}

prompt_for_config() {
    log "Borg configuration file not found. Prompting for config..."
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
        log "Generated secure BORG_PASSPHRASE."
    fi

cat <<EOF > $BORG_CONFIG_FILE
remote_ssh_port="$remote_ssh_port"
remote_ssh_key="$remote_ssh_key"
email_address="$EMAIL_RECIPIENT"
USERNAME="$USERNAME"
remote_server_address="$remote_server_address"
remote_storage_location="\$USERNAME@\$remote_server_address:\$remote_ssh_port/mount/\$USERNAME/borg"
BACKUP_LOCATIONS="$DEFAULT_BACKUP_LOCATIONS"
EXCLUDE_LIST="$DEFAULT_EXCLUDE_LIST"
KEEP_WITHIN="$DEFAULT_KEEP_WITHIN"
KEEP_DAILY="$DEFAULT_KEEP_DAILY"
KEEP_WEEKLY="$DEFAULT_KEEP_WEEKLY"
KEEP_MONTHLY="$DEFAULT_KEEP_MONTHLY"

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=ssh://\$remote_storage_location
export BORG_RSH="ssh -4 -i \$remote_ssh_key"
export BORG_PASSPHRASE='$BORG_PASSPHRASE'
EOF

    log "Borg configuration file created at $BORG_CONFIG_FILE."
}

initialize_borg_repo() {
    if ! $BORG_CMD info > /dev/null 2>&1; then
        log "Borg repository not initialized. Initializing now."
        if $BORG_CMD init -e repokey; then
            log "Borg repository initialized successfully."
            $BORG_CMD key export :: > $TEMP_DIR/repo-key.bak
            log "Borg repository key exported."
        else
            log "Failed to initialize Borg repository."
            exit 1
        fi
    else
        log "Borg repository already initialized."
    fi
}

update_script() {
    log "Checking for script updates..."
    LATEST_VERSION=$($CURL_CMD -sSL $VERSION_URL)
    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        log "Updating script from $GITHUB_URL..."
        if $CURL_CMD -o "$0" -sSL "$GITHUB_URL" && chmod +x "$0"; then
            log "Script updated to version $LATEST_VERSION."
            exit 0
        else
            log "Failed to update script."
            exit 1
        fi
    else
        log "You are already using the latest version ($SCRIPT_VERSION)."
        exit 0
    fi
}

force_update_script() {
    log "Forcing script update from $GITHUB_URL..."
    if $CURL_CMD -o "$0" -sSL "$GITHUB_URL" && chmod +x "$0"; then
        log "Script reinstalled successfully."
        exit 0
    else
        log "Failed to force update script."
        exit 1
    fi
}

trap 'log "Backup interrupted"; handle_exit 2; exit 2' INT TERM

log "Checking installation..."
check_installation

# Parse command-line arguments
while getopts ":c:l:e:s:w:f:r:uvh-:" opt; do
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
      if [ "$OPTARG" = "--force" ]; then
          force_update_script
      else
          update_script
      fi
      ;;
    v )
      show_version
      exit 0
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
        update=force)
          force_update_script
          ;;
        version)
          show_version
          exit 0
          ;;
        remote)
          REMOTE_PATH="$2"
          shift
          ;;
        keep-within)
          KEEP_WITHIN="$2"
          shift
          ;;
        keep-daily)
          KEEP_DAILY="$2"
          shift
          ;;
        keep-weekly)
          KEEP_WEEKLY="$2"
          shift
          ;;
        keep-monthly)
          KEEP_MONTHLY="$2"
          shift
          ;;
        *)
          log "Invalid option: --${OPTARG}"
          show_help
          exit 1
          ;;
      esac
      ;;
    \? )
      log "Invalid option: $OPTARG"
      show_help
      exit 1
      ;;
    : )
      log "Invalid option: $OPTARG requires an argument"
      show_help
      exit 1
      ;;
  esac
done

log "Check that borg is installed"
check_borg_installed  || { log "Failed during borg installation check."; exit 1; }

log "Checking for sendmail installation..."
check_sendmail_installed || { log "Failed during sendmail check."; exit 1; }

log "Checking for GPG key installation..."
check_gpg_key_installed || { log "Failed during GPG key check."; exit 1; }

log "Checking if the borg config exists"
if [ ! -f "$BORG_CONFIG_FILE" ]; then
    prompt_for_config
fi

log "Importing $BORG_CONFIG_FILE"
. $BORG_CONFIG_FILE

# Use BACKUP_LOCATIONS from config file if not set by command-line argument
if [ -z "$BACKUP_LOCATIONS" ]; then
    BACKUP_LOCATIONS="$DEFAULT_BACKUP_LOCATIONS"
fi

# Use EXCLUDE_LIST from config file if not set by command-line argument
if [ -z "$EXCLUDE_LIST" ]; then
    EXCLUDE_LIST="$DEFAULT_EXCLUDE_LIST"
fi

# Use prune options from config file if not set by command-line argument
KEEP_WITHIN=${KEEP_WITHIN:-$DEFAULT_KEEP_WITHIN}
KEEP_DAILY=${KEEP_DAILY:-$DEFAULT_KEEP_DAILY}
KEEP_WEEKLY=${KEEP_WEEKLY:-$DEFAULT_KEEP_WEEKLY}
KEEP_MONTHLY=${KEEP_MONTHLY:-$DEFAULT_KEEP_MONTHLY}

log "Checking if Borg repo needs to be initialized"
initialize_borg_repo

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

log "Starting Backup with locations: $BACKUP_LOCATIONS"
log "Excluding: $EXCLUDE_OPTS"

# Backup
if ! $BORG_CMD create --verbose --filter AME --list --stats --show-rc --compression lz4 --exclude-caches $EXCLUDE_OPTS $REMOTE_OPTS ::'{hostname}-{now}' $BACKUP_LOCATIONS 2>&1 | $TEE_CMD -a $OUTPUT_FILE; then
    log "Borg create command failed."
    handle_exit 1
    exit 1
fi

backup_exit=${PIPESTATUS[0]}

log "Pruning Repository"
log "$BORG_CMD prune --list --glob-archives '{hostname}-*' --show-rc --keep-within $KEEP_WITHIN --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY $REMOTE_OPTS"

# Prune
if ! $BORG_CMD prune --list --glob-archives '{hostname}-*' --show-rc \
    --keep-within $KEEP_WITHIN \
    --keep-daily $KEEP_DAILY \
    --keep-weekly $KEEP_WEEKLY \
    --keep-monthly $KEEP_MONTHLY $REMOTE_OPTS 2>&1 | $TEE_CMD -a $OUTPUT_FILE; then
    log "Borg prune command failed."
    handle_exit 1
    exit 1
fi

prune_exit=${PIPESTATUS[0]}
compact_exit=0  # Assuming compact command or similar would go here

# Determine global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

handle_exit $global_exit

# Cleanup
rm -rf $TEMP_DIR

exit $global_exit
