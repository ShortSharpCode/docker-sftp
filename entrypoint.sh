#!/bin/bash

# Copyright (c) 2014, Patrik Nilsson
# All rights reserved.

# This script is licensed under the BSD 2-Clause License.
# See LICENSE file for full legal information.

set -e

: ${SFTP_USER:=sftp1}
: ${SFTP_UID:=2001}
: ${SFTP_CHROOT:=/chroot}
: ${SFTP_LOG_LEVEL:=INFO}

# Edit settings in relevant config files
set_config() {
    key="$1"
    value="$2"
    if [ "$config_file" = "$CONF_SSH/sshd_config" ]; then
        sed -ri "s|($key).*|\1 $value|g" $config_file
    fi
}

config_file="$CONF_SSH/sshd_config"
set_config 'LogLevel' "$SFTP_LOG_LEVEL"
set_config 'ChrootDirectory' "$SFTP_CHROOT"

: ${SFTP_DATA_DIR:=/data/sftp}

# Check for the existance of the default, or a specified, data volume.
echo >&2 'Searching for mounted data volumes...'
if ! [ -e $SFTP_DATA_DIR ]; then
	echo >&2 'Warning: data volume not found!'
	echo >&2 ' Did you forget to do --volumes-from data-container ?'
	echo >&2 ' If you choose to not use a data volume container, feel free to ignore this.'
else
	# Set chroot to data volume container
	: ${SFTP_CHROOT:=$SFTP_DATA_DIR/chroot}
	set_config 'ChrootDirectory' "$SFTP_CHROOT"
	# If no old data exist on volume, transfer persistant data.
	if [ -e $SFTP_DATA_DIR/etc/ssh ]; then
		echo >&2 'Data volume found! But data already exists - skipping...'
	else
		echo >&2 'Data volume found! - copying now...'
		mkdir -p ${SFTP_DATA_DIR}${CONF_SSH}
		cp -ax $CONF_SSH/* ${SFTP_DATA_DIR}${CONF_SSH}/
		echo >&2 "Complete! Persistant data has successfully been copied to $SFTP_DATA_DIR."
	fi
	# Symlink ssh config and keys to data volume
	rm $CONF_SSH/*
	ln -s ${SFTP_DATA_DIR}${CONF_SSH}/* ${CONF_SSH}/
fi

: ${SFTP_HOME:=$SFTP_CHROOT/share}

# Create and setup chroot and sftp home
mkdir -p $SFTP_HOME && chmod 555 $SFTP_CHROOT
chmod 775 $SFTP_HOME && chmod g+s $SFTP_HOME
chgrp sftpusers $SFTP_HOME

# Check not only for existance of user, but if either username or uid is in use.
CHECK1=$(getent passwd $SFTP_USER > /dev/null; echo $?)
CHECK2=$(getent passwd $SFTP_UID > /dev/null; echo $?)

# Check for conflicts, then do user setup.
if [ $CHECK1 -eq 0 -o $CHECK2 -eq 0 ]; then
	echo >&2 'Warning: a conflict in the user setup detected! - skipping...'
	echo >&2 ' This should only occur under two conditions:'
	echo >&2 '  1. You are updating or migrating the container, in which case this is normal.'
	echo >&2 '  2. You have chosen to bind mount auth files from the host.'
	echo >&2 ' If neither of these are true, the instance may not work properly (no sftp user login).'
else
	useradd -Ud /share -u $SFTP_UID -s /usr/sbin/nologin -G sftpusers $SFTP_USER
	if [ -z $SFTP_PASS ]; then SFTP_PASS=`pwgen -scnB1 12`; fi
	echo $SFTP_PASS > sftp_pass; chmod 600 sftp_pass
	echo "$SFTP_USER:$SFTP_PASS" | chpasswd && unset SFTP_PASS

	# Echo quickstart guide to logs
	echo
	echo '================================================================================='
	echo 'Your sftp container is now ready to use!'
	echo
	echo 'Login to your new sftp container with these credentials:'
	echo "Username: $SFTP_USER"
	echo
	echo 'For security reasons passwords are not listed here.'
	echo 'To get the password run this:'
	echo "docker cp some-container:/sftp_pass"
	echo
	echo 'For more information, see the official README.md'
	echo 'Link: http://registry.hub.docker.com/u/asavartzeth/sftp/'
	echo 'Link: http://github.com/AsavarTzeth/docker-sftp/'
	echo '================================================================================='
fi

echo "Deployment completed!"

exec "$@"
