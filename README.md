# Collective Backup Script

## Overview

The **Collective** script is a robust backup solution that leverages BorgBackup to securely back up specified directories to a remote location. The script includes features for installation, configuration, and self-updating from a GitHub repository. GPG encryption is used for secure email communications.

## Features

- Automated backup of specified directories using BorgBackup.
- GPG encryption for secure email notifications.
- Customizable configuration file.
- Installation prompt to `/usr/bin/collective`.
- Automatic script updates from GitHub.
- Sendmail integration for email notifications.

## Installation

On the first run, the script will prompt you to install it to `/usr/bin/collective`. The default response is "yes". This ensures that the script can be run easily from anywhere on your system.

## Usage

Run the script with appropriate options to configure and perform backups. Below are the available options:

### Options

- `-c FILE` : Specify the Borg configuration file (default: `/root/.borg.settings`).
- `-l DIRS` : Specify the directories to back up as a space-separated list (default: `/etc /home /root /mount /var`).
- `-e EXCLUDES` : Specify paths to exclude as a comma-separated list (e.g., `home/*/.cache/*,var/tmp/*`).
- `-s CMD` : Command to run on successful completion.
- `-w CMD` : Command to run on completion with warnings.
- `-f CMD` : Command to run on failure.
- `-u, --update` : Update the script to the latest version from GitHub.
- `-h, --help` : Show help message and exit.

### Example

```sh
collective -c /path/to/config -l "/etc /var" -e "home/*/.cache/*,var/tmp/*" -s "echo Backup Successful" -w "echo Backup Completed with Warnings" -f "echo Backup Failed"

```
## Configuration

If the Borg configuration file does not exist, the script will prompt for necessary configuration details:

    Remote username
    Remote server address (default: borg.sarik.tech)
    Remote SSH port (default: 22)
    Remote SSH key path (default: /root/.ssh/borg)
    Borg passphrase (leave empty to generate one)

The configuration will be saved to /root/.borg.settings.

### Example Configuration File

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

## Dependencies

The script ensures the following dependencies are installed:

    BorgBackup
    GPG (for email encryption)
    Sendmail

The script will attempt to install these dependencies if they are not found.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Author

Developed by [DisappointingSupernova](https://github.com/disappointingsupernova). For support, contact github@disappointingsupernova.space.