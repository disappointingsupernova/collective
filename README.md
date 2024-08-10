# Collective Backup Script

## Overview

The **Collective** script is a comprehensive backup solution that utilizes BorgBackup to securely back up specified directories, including MySQL databases, to a remote location. It supports features like GPG encryption for secure email notifications, MySQL database backups, customizable configuration, and self-updating from a GitHub repository.

## Features

- **Automated Directory Backup**: Backs up specified directories using BorgBackup.
- **MySQL Database Backup**: Option to back up all or specific MySQL databases.
- **GPG Encryption**: Secure email notifications using GPG encryption.
- **Customizable Configuration**: Easily customizable configuration file for flexible setup.
- **Installation Prompt**: Automatically installs to `/usr/bin/collective` for easy execution.
- **Automatic Updates**: Self-updates from the GitHub repository.
- **Sendmail Integration**: Integrates with Sendmail for email notifications.
- **Flexible Pruning Options**: Supports a variety of retention policies for backups.
- **Dry Run Mode**: Test the backup process without making any actual changes.

## Installation

On the first run, the script will prompt you to install it to `/usr/bin/collective`. The default response is "yes". This allows the script to be easily executed from anywhere on your system.

## Usage

Run the script with the appropriate options to configure and perform backups. Below are the available options:

### Options

- `-c FILE` : Specify the Borg configuration file (default: `/root/.borg.settings`).
- `-l DIRS` : Specify the directories to back up as a space-separated list (default: `/etc /home /root /var`).
- `-e EXCLUDES` : Specify paths to exclude as a comma-separated list (e.g., `home/*/.cache/*,var/tmp/*`).
- `-s CMD` : Command to run on successful completion.
- `-w CMD` : Command to run on completion with warnings.
- `-f CMD` : Command to run on failure.
- `-r, --remote PATH` : Specify the remote path for Borg operations.
- `-u, --update` : Update the script to the latest version from GitHub.
- `-u, --update=force` : Force update the script to the latest version from GitHub, even if the current version is the latest.
- `-v, --version` : Show the script version and exit.
- `-h, --help` : Show help message and exit.
- `--keep-within TIME` : Specify the time interval to keep backups (default: `14d`).
- `--keep-hourly N` : Specify the number of hourly backups to keep (default: `24`).
- `--keep-daily N` : Specify the number of daily backups to keep (default: `28`).
- `--keep-weekly N` : Specify the number of weekly backups to keep (default: `8`).
- `--keep-monthly N` : Specify the number of monthly backups to keep (default: `48`).
- `--mysql-backup [DB_NAME]` : Backup MySQL databases. Use `all` for all databases or specify a database name. If no database is specified, `all` is assumed.
- `--mysql-backup-gzip` : Compress the MySQL backup with gzip.
- `--leave-sql-backup` : Do not delete the SQL backup after the Borg backup.
- `--dry-run` : Perform a trial run with no changes made.

### Example

```sh
collective -c /path/to/config -l "/etc /var" -e "home/*/.cache/*,var/tmp/*" --mysql-backup all --mysql-backup-gzip --keep-daily 14 --dry-run
```

## MySQL Backup

The script allows for backing up MySQL databases:

    All Databases: Use `--mysql-backup` all or simply --mysql-backup to back up all databases.
    Specific Database: Use --mysql-backup <database_name> to back up a specific database.
    Compression: Add the --mysql-backup-gzip flag to compress the backup files.
    SQL Backup Directory: The MySQL backup files are stored in /backups/Collective/mysql/.
    SQL Backup Cleanup: By default, the SQL backups are deleted after the Borg backup. Use --leave-sql-backup to keep the SQL backups on disk.

## Configuration

If the Borg configuration file does not exist, the script will prompt for necessary configuration details:

    Remote username
    Remote server address (default: borg.sarik.tech)
    Remote SSH port (default: 22)
    Remote SSH key path (default: /root/.ssh/borg)
    Borg passphrase (leave empty to generate one)

The configuration will be saved to /root/.borg.settings.
Example Configuration File

``` sh
remote_ssh_port="22"
remote_ssh_key="/root/.ssh/borg"
email_address="hostname@sarik.tech"
USERNAME="username"
remote_server_address="borg.sarik.tech"
remote_storage_location="\$USERNAME@\$remote_server_address:\$remote_ssh_port/mount/\$USERNAME/borg"

# Setting this, so the repo does not need to be given on the commandline:
export BORG_REPO=ssh://\$remote_storage_location
export BORG_RSH="ssh -4 -i \$remote_ssh_key"
export BORG_PASSPHRASE='generated_passphrase'
```

## Update Script

The script includes a self-update feature. Run the script with the --update or -u option to check for and apply updates from the GitHub repository.

``` sh
collective --update
```

To force an update, even if the current version is the latest:

``` sh
collective --update=force
```

## Dependencies

The script ensures the following dependencies are installed:

    BorgBackup: For backup operations.
    GPG: For email encryption.
    Sendmail: For sending email notifications.
    MySQL/MariaDB: For MySQL backup functionality.

The script will attempt to install these dependencies if they are not found.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Author

Developed by DisappointingSupernova. For support, contact github@disappointingsupernova.space.