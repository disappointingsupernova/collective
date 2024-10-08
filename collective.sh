#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
GITHUB_ACCOUNT="disappointingsupernova"
REPO_NAME="collective"
SCRIPT_NAME="collective.sh"
DISPLAY_NAME="Collective"
GITHUB_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/$SCRIPT_NAME"
VERSION_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/$REPO_NAME/main/VERSION"

# Source check: If the script is being sourced for auto-completion, register the completion and return
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    _collective_completions
    return 0
fi

# Determine the script's own path
SCRIPT_PATH=$(realpath "$0")

# Function to find the full path of a command
function find_command() {
    local cmd="$1"
    local path
    path=$(which "$cmd")
    if [ -z "$path" ]; then
        logger "Command $cmd not found. Please ensure it is installed and available in your PATH."
        echo "Command $cmd not found. Please ensure it is installed and available in your PATH."
        exit 1
    fi
    echo "$path"
}

SENDMAIL_CMD=$(find_command sendmail)
GPG_CMD=$(find_command gpg)
CURL_CMD=$(find_command curl)
BORG_CMD=$(find_command borg)
MYSQLDUMP_CMD=$(find_command mysqldump)
TEE_CMD=$(find_command tee)
LOGGER_CMD=$(find_command logger)

TEMP_DIR=$(mktemp -d) || { echo "Failed to create temporary directory"; exit 1; }
OUTPUT_FILE="$TEMP_DIR/${REPO_NAME}_pgp_message.txt"

log() {
    local level="$1"
    shift
    local message="$(date) [$level] $*"
    echo "$message" | $TEE_CMD -a $OUTPUT_FILE
    echo "$message" | $LOGGER_CMD -t "$DISPLAY_NAME"
} || {
    echo "$(date) [ERROR] Failed to log message: $message" >> "$OUTPUT_FILE"
}

log "INFO" "GitHub settings initialized."
log "INFO" "All necessary commands have been located."
log "INFO" "Temporary directory created: $TEMP_DIR"
log "INFO" "Logging initialized."

# Change to a safe directory
cd /tmp || { echo "Failed to change directory to /tmp"; exit 1; }
log "INFO" "Changed to /tmp directory."

# Script version
SCRIPT_VERSION="1.1.3"
log "INFO" "Script version: $SCRIPT_VERSION"

EMAIL_RECIPIENT="$(hostname)@sarik.tech"
log "INFO" "Email recipient set to $EMAIL_RECIPIENT"

# Default settings
BORG_CONFIG_FILE="/root/.borg.settings"
REMOTE_PATH=""
DEFAULT_BACKUP_LOCATIONS="/etc /home /root /var"
DEFAULT_EXCLUDE_LIST="home/*/.cache/*,var/tmp/* "
ON_SUCCESS=""
ON_WARNING=""
ON_FAILURE=""
DEFAULT_KEEP_WITHIN="14d"
DEFAULT_KEEP_HOURLY="24"
DEFAULT_KEEP_DAILY="28"
DEFAULT_KEEP_WEEKLY="8"
DEFAULT_KEEP_MONTHLY="48"
GPG_KEY_FINGERPRINT="7D2D35B359A3BB1AE7A2034C0CB5BB0EFE677CA8"
log "INFO" "Default settings initialized."

log "INFO" "Script Path: $SCRIPT_PATH"

# Function to check if the script is installed in /usr/bin/$REPO_NAME
check_installation() {
    if [ ! -f /usr/bin/$REPO_NAME ]; then
        read -p "Do you want to install $DISPLAY_NAME to /usr/bin/$REPO_NAME? [Y/n]: " response
        response=${response:-yes}
        if [[ "$response" =~ ^[Yy] ]]; then
            log "INFO" "Installing $DISPLAY_NAME to /usr/bin/$REPO_NAME..."
            if cp "$SCRIPT_PATH" /usr/bin/$REPO_NAME; then
                chmod +x /usr/bin/$REPO_NAME
                log "INFO" "$DISPLAY_NAME installed successfully to /usr/bin/$REPO_NAME."
                log "INFO" "Removing script from the current location."
                rm -f "$SCRIPT_PATH"
                exit 0
            else
                log "ERROR" "Failed to install $DISPLAY_NAME to /usr/bin/$REPO_NAME."
            fi
        else
            log "INFO" "Skipping installation to /usr/bin/$REPO_NAME."
        fi
    else
        log "INFO" "$DISPLAY_NAME is already installed in /usr/bin/$REPO_NAME."
    fi
}

validate_config() {
    local config_file="$1"

    log "INFO" "Validating configuration file: $config_file"

    if [ ! -f "$config_file" ]; then
        log "ERROR" "Configuration file $config_file not found!"
        exit 1
    fi

    # Load the configuration file
    source "$config_file"

    # Check required variables
    if [ -z "$remote_ssh_port" ]; then
        log "ERROR" "Configuration error: 'remote_ssh_port' is not set."
        exit 1
    fi

    if [ -z "$remote_ssh_key" ] || [ ! -f "$remote_ssh_key" ]; then
        log "ERROR" "Configuration error: 'remote_ssh_key' is not set or does not exist."
        exit 1
    fi

    if [ -z "$remote_server_address" ]; then
        log "ERROR" "Configuration error: 'remote_server_address' is not set."
        exit 1
    fi

    if [ -z "$USERNAME" ]; then
        log "ERROR" "Configuration error: 'USERNAME' is not set."
        exit 1
    fi

    if [ -z "$BORG_PASSPHRASE" ]; then
        log "ERROR" "Configuration error: 'BORG_PASSPHRASE' is not set."
        exit 1
    fi

    if [ -z "$BACKUP_LOCATIONS" ]; then
        log "ERROR" "Configuration error: 'BACKUP_LOCATIONS' is not set."
        exit 1
    fi

    if [ -z "$KEEP_WITHIN" ]; then
        log "ERROR" "Configuration error: 'KEEP_WITHIN' is not set."
        exit 1
    fi

    log "INFO" "Configuration file validated successfully."
}

send_email() {
    if ! $GPG_CMD --sign --encrypt -a -r $GPG_KEY_FINGERPRINT $OUTPUT_FILE; then
        log "ERROR" "Failed to sign and encrypt email."
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
        log "ERROR" "Failed to send email."
        return 1
    fi

    log "INFO" "Email sent successfully to $EMAIL_RECIPIENT."
}

handle_exit() {
    EXIT_CODE=$1
    FAILED_FLAG_FILE="/root/.borglastrun.failed"

    if [ $EXIT_CODE -eq 0 ]; then
        log "INFO" "Backup and Prune finished successfully"
        [ -n "$ON_SUCCESS" ] && eval "$ON_SUCCESS"
        SUBJECT="borg SUCCESS: $(hostname) - $DISPLAY_NAME"
        
        # Remove the failed flag file if it exists
        if [ -f "$FAILED_FLAG_FILE" ]; then
            rm -f "$FAILED_FLAG_FILE"
            log "INFO" "Removed $FAILED_FLAG_FILE after successful backup."
        fi
        
    elif [ $EXIT_CODE -eq 1 ]; then
        log "WARNING" "Backup and Prune finished with warnings"
        [ -n "$ON_WARNING" ] && eval "$ON_WARNING"
        SUBJECT="borg WARNING: $(hostname) - $remote_storage_location - $DISPLAY_NAME"
    else
        log "ERROR" "Backup and Prune finished with errors"
        [ -n "$ON_FAILURE" ] && eval "$ON_FAILURE"
        SUBJECT="borg FAILURE: $(hostname) @ $(date) - $remote_storage_location - $DISPLAY_NAME"
        
        # Create the failed flag file
        echo "1" > "$FAILED_FLAG_FILE"
        log "INFO" "Created $FAILED_FLAG_FILE due to backup failure."
    fi

    send_email "$SUBJECT"
    rm -rf $TEMP_DIR
    echo "Cleaned up temporary files." | $LOGGER_CMD -t "$DISPLAY_NAME"
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
  --keep-hourly    Specify the number of hourly backups to keep (default: 24)
                   Example: --keep-hourly 24
  --keep-daily     Specify the number of daily backups to keep (default: 28)
                   Example: --keep-daily 14
  --keep-weekly    Specify the number of weekly backups to keep (default: 8)
                   Example: --keep-weekly 4
  --keep-monthly   Specify the number of monthly backups to keep (default: 48)
                   Example: --keep-monthly 12
  --mysql-backup   Backup MySQL database(s). Use 'all' for all databases or specify a database name.
                   Example: --mysql-backup all
                   Example: --mysql-backup database_name
  --mysql-backup-gzip  Compress the MySQL backup with gzip.
  --leave-sql-backup   Do not delete the SQL backup after the Borg backup.
  --dry-run        Perform a trial run with no changes made"
}

show_version() {
    echo "$DISPLAY_NAME version $SCRIPT_VERSION"
}

install_borg() {
    if [ -f /etc/debian_version ]; then
        log "INFO" "Installing BorgBackup on Debian-based system..."
        apt-get update && apt-get install -y borgbackup || { log "ERROR" "Failed to install BorgBackup on Debian-based system."; exit 1; }
    elif [ -f /etc/redhat-release ]; then
        log "INFO" "Installing BorgBackup on RedHat-based system..."
        yum install -y epel-release && yum install -y borgbackup || { log "ERROR" "Failed to install BorgBackup on RedHat-based system."; exit 1; }
    else
        log "ERROR" "Unsupported OS. Please install BorgBackup manually."
        exit 1
    fi
    log "INFO" "BorgBackup installed successfully."
}

install_sendmail() {
    if [ -f /etc/debian_version ]; then
        log "INFO" "Installing sendmail on Debian-based system..."
        apt-get install -y sendmail || { log "ERROR" "Failed to install sendmail on Debian-based system."; exit 1; }
    elif [ -f /etc/redhat-release ]; then
        log "INFO" "Installing sendmail on RedHat-based system..."
        yum install -y sendmail || { log "ERROR" "Failed to install sendmail on RedHat-based system."; exit 1; }
    else
        log "ERROR" "Unsupported OS. Please install sendmail manually."
        exit 1
    fi
    log "INFO" "sendmail installed successfully."
}

check_borg_installed() {
    if ! $BORG_CMD > /dev/null; then
        log "INFO" "BorgBackup not found. Installing..."
        install_borg
    else
        log "INFO" "BorgBackup is already installed."
    fi
}

check_sendmail_installed() {
    log "INFO" "sendmail check function invoked"
    if ! command -v sendmail > /dev/null; then
        log "INFO" "sendmail not found. Installing..."
        install_sendmail
    else
        log "INFO" "sendmail is already installed."
    fi
}

check_gpg_key_installed() {
    if ! $GPG_CMD --list-keys $GPG_KEY_FINGERPRINT > /dev/null 2>&1; then
        log "INFO" "GPG key with fingerprint $GPG_KEY_FINGERPRINT not found. Importing..."
        if ! $GPG_CMD --keyserver keyserver.ubuntu.com --recv-keys $GPG_KEY_FINGERPRINT; then
            log "ERROR" "Failed to import GPG key."
            exit 1
        fi
    fi
    log "INFO" "GPG key is installed."
}

generate_passphrase() {
    openssl rand -base64 256 | tr -d '\n'
}

prompt_for_config() {
    log "INFO" "Borg configuration file not found. Prompting for config..."
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
        log "INFO" "Generated secure BORG_PASSPHRASE."
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
KEEP_HOURLY="$DEFAULT_KEEP_HOURLY"
KEEP_DAILY="$DEFAULT_KEEP_DAILY"
KEEP_WEEKLY="$DEFAULT_KEEP_WEEKLY"
KEEP_MONTHLY="$DEFAULT_KEEP_MONTHLY"

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=ssh://\$remote_storage_location
export BORG_RSH="ssh -4 -i \$remote_ssh_key"
export BORG_PASSPHRASE='$BORG_PASSPHRASE'
EOF

    log "INFO" "Borg configuration file created at $BORG_CONFIG_FILE."
}

initialize_borg_repo() {
    if ! $BORG_CMD $REMOTE_OPTS info > /dev/null 2>&1; then
        log "INFO" "Borg repository not initialized. Initializing now."
        if $BORG_CMD $REMOTE_OPTS init -e repokey; then
            log "INFO" "Borg repository initialized successfully."
            $BORG_CMD $REMOTE_OPTS key export :: > $TEMP_DIR/repo-key.bak
            cat $TEMP_DIR/repo-key.bak
            log "INFO" "Borg repository key exported."
        else
            log "ERROR" "Failed to initialize Borg repository."
            exit 1
        fi
    else
        log "INFO" "Borg repository already initialized."
    fi
}

mysql_backup() {
    local backup_dir="/backups/$DISPLAY_NAME/mysql"
    mkdir -p "$backup_dir"

    if [ -z "$MYSQL_BACKUP" ] || [ "$MYSQL_BACKUP" == "all" ]; then
        log "INFO" "Backing up all MySQL databases"
        backup_file="$backup_dir/all_databases_$(date +%F_%T).sql"
        if [ "$MYSQL_BACKUP_GZIP" = true ]; then
            backup_file="${backup_file}.gz"
            if ! $MYSQLDUMP_CMD --single-transaction --all-databases | gzip > "$backup_file"; then
                log "ERROR" "Failed to backup all MySQL databases"
                handle_exit 1
            fi
        else
            if ! $MYSQLDUMP_CMD --single-transaction --all-databases > "$backup_file"; then
                log "ERROR" "Failed to backup all MySQL databases"
                handle_exit 1
            fi
        fi
        log "INFO" "All MySQL databases backed up to $backup_file"
    else
        log "INFO" "Backing up MySQL database: $MYSQL_BACKUP"
        backup_file="$backup_dir/${MYSQL_BACKUP}_$(date +%F_%T).sql"
        if [ "$MYSQL_BACKUP_GZIP" = true ]; then
            backup_file="${backup_file}.gz"
            if ! $MYSQLDUMP_CMD --single-transaction "$MYSQL_BACKUP" | gzip > "$backup_file"; then
                log "ERROR" "Failed to backup MySQL database: $MYSQL_BACKUP"
                handle_exit 1
            fi
        else
            if ! $MYSQLDUMP_CMD --single-transaction "$MYSQL_BACKUP" > "$backup_file"; then
                log "ERROR" "Failed to backup MySQL database: $MYSQL_BACKUP"
                handle_exit 1
            fi
        fi
        log "INFO" "MySQL database $MYSQL_BACKUP backed up to $backup_file"
    fi

    # Add the backup directory to the backup locations
    BACKUP_LOCATIONS="$BACKUP_LOCATIONS $backup_dir"
}

update_script() {
    log "INFO" "Checking for script updates..."
    LATEST_VERSION=$($CURL_CMD -sSL $VERSION_URL)
    if [ "$LATEST_VERSION" != "$SCRIPT_VERSION" ]; then
        log "INFO" "Updating script from $GITHUB_URL..."
        if $CURL_CMD -o "$0" -sSL "$GITHUB_URL" && chmod +x "$0"; then
            log "INFO" "Script updated to version $LATEST_VERSION."
            exit 0
        else
            log "ERROR" "Failed to update script."
            exit 1
        fi
    else
        log "INFO" "You are already using the latest version ($SCRIPT_VERSION)."
        exit 0
    fi
}

force_update_script() {
    log "INFO" "Forcing script update from $GITHUB_URL..."
    if $CURL_CMD -o "$0" -sSL "$GITHUB_URL" && chmod +x "$0"; then
        log "INFO" "Script reinstalled successfully."
        exit 0
    else
        log "ERROR" "Failed to force update script."
        exit 1
    fi
}

trap 'log "ERROR" "Backup interrupted"; handle_exit 2; exit 2' INT TERM

log "INFO" "Checking installation..."
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
        keep-hourly)
          KEEP_HOURLY="$2"
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
        mysql-backup)
          MYSQL_BACKUP="${2:-all}"
          shift
          ;;
        mysql-backup-gzip)
          MYSQL_BACKUP_GZIP=true
          ;;
        leave-sql-backup)
          LEAVE_SQL_BACKUP=true
          ;;
        dry-run)
          DRY_RUN=true
          ;;
        *)
          log "ERROR" "Invalid option: --${OPTARG}"
          show_help
          exit 1
          ;;
      esac
      ;;
    \? )
      log "ERROR" "Invalid option: $OPTARG"
      show_help
      exit 1
      ;;
    : )
      log "ERROR" "Invalid option: $OPTARG requires an argument"
      show_help
      exit 1
      ;;
  esac
done

log "INFO" "Check that borg is installed"
check_borg_installed  || { log "ERROR" "Failed during borg installation check."; exit 1; }

log "INFO" "Checking for sendmail installation..."
check_sendmail_installed || { log "ERROR" "Failed during sendmail check."; exit 1; }

log "INFO" "Checking for GPG key installation..."
check_gpg_key_installed || { log "ERROR" "Failed during GPG key check."; exit 1; }

log "INFO" "Checking if the borg config exists"
if [ ! -f "$BORG_CONFIG_FILE" ]; then
    prompt_for_config
fi

log "INFO" "Checking if the borg config is valid"
validate_config "$BORG_CONFIG_FILE"

log "INFO" "Importing $BORG_CONFIG_FILE"
. $BORG_CONFIG_FILE

# Perform MySQL backup if requested
if [ -n "$MYSQL_BACKUP" ]; then
    mysql_backup
fi

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
KEEP_HOURLY=${KEEP_HOURLY:-$DEFAULT_KEEP_HOURLY}
KEEP_DAILY=${KEEP_DAILY:-$DEFAULT_KEEP_DAILY}
KEEP_WEEKLY=${KEEP_WEEKLY:-$DEFAULT_KEEP_WEEKLY}
KEEP_MONTHLY=${KEEP_MONTHLY:-$DEFAULT_KEEP_MONTHLY}

# Prepare remote path option
REMOTE_OPTS=""
if [ -n "$REMOTE_PATH" ]; then
    REMOTE_OPTS="--remote-path=$REMOTE_PATH"
fi

log "INFO" "Checking if Borg repo needs to be initialized"
initialize_borg_repo

# Prepare exclude options
IFS=',' read -ra EXCLUDES <<< "$EXCLUDE_LIST"
EXCLUDE_OPTS=""
for EXCLUDE in "${EXCLUDES[@]}"; do
    EXCLUDE_OPTS+="--exclude $EXCLUDE "
done

log "INFO" "Starting Backup with locations: $BACKUP_LOCATIONS"
log "INFO" "Excluding: $EXCLUDE_OPTS"
log "INFO" "$BORG_CMD create ${DRY_RUN:+--dry-run} --verbose --filter AME --list --stats --show-rc --compression lz4 --exclude-caches $EXCLUDE_OPTS $REMOTE_OPTS ::'{hostname}-{now}' $BACKUP_LOCATIONS"

# Backup
if ! $BORG_CMD create ${DRY_RUN:+--dry-run} --verbose --filter AME --list --stats --show-rc --compression lz4 --exclude-caches $EXCLUDE_OPTS $REMOTE_OPTS ::'{hostname}-{now}' $BACKUP_LOCATIONS 2>&1 | $TEE_CMD -a $OUTPUT_FILE; then
    log "ERROR" "Borg create command failed."
    handle_exit 1
    exit 1
fi

backup_exit=${PIPESTATUS[0]}

log "INFO" "Pruning Repository"
log "INFO" "$BORG_CMD prune ${DRY_RUN:+--dry-run} --list --glob-archives '{hostname}-*' --show-rc --keep-within $KEEP_WITHIN --keep-hourly $KEEP_HOURLY --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY $REMOTE_OPTS"

# Prune
if ! $BORG_CMD prune ${DRY_RUN:+--dry-run} --list --glob-archives '{hostname}-*' --show-rc \
    --keep-within $KEEP_WITHIN \
    --keep-hourly $KEEP_HOURLY \
    --keep-daily $KEEP_DAILY \
    --keep-weekly $KEEP_WEEKLY \
    --keep-monthly $KEEP_MONTHLY $REMOTE_OPTS 2>&1 | $TEE_CMD -a $OUTPUT_FILE; then
    log "ERROR" "Borg prune command failed."
    handle_exit 1
    exit 1
fi

prune_exit=${PIPESTATUS[0]}
compact_exit=0  # Assuming compact command or similar would go here

# Determine global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))
global_exit=$(( compact_exit > global_exit ? compact_exit : global_exit ))

handle_exit $global_exit

# Cleanup SQL backups if not told to leave them
if [ -z "$LEAVE_SQL_BACKUP" ]; then
    log "INFO" "Deleting SQL backup files..."
    rm -rf /backups/$DISPLAY_NAME/mysql
    log "INFO" "SQL backup files deleted."
fi

# Cleanup
rm -rf $TEMP_DIR

exit $global_exit

# Function to provide autocomplete for options
_collective_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="--help --version --update --update=force --remote --keep-within --keep-hourly --keep-daily --keep-weekly --keep-monthly --mysql-backup --mysql-backup-gzip --leave-sql-backup --dry-run -c -l -e -s -w -f -r -u -v -h"

    COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
    return 0
}

# Register the autocomplete function for this script
complete -F _collective_completions "$(basename "$0")"
