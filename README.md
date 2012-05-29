Liferay Backup Script
======================

This perl script can be used in combination with your other backup scripts to 
create a consistent backup of both Liferay database and document library data
directory.

## Requirements

* Perl with DBI
* rsync in path
* mysqldump in path
* Linux LVM with lvcreate and lvremove in path
* mount and umount in path

## Install

1. First clone this repository to a directory of you choice

	$ git clone git://github.com/mikakoivisto/liferay-backup.git

2. Add the liferay-backup directory to your path or reference it with complete
path from your backup script.

3. Create a backup user to your database with LOCK TABLES, SELECT, FILE, RELOAD,
SUPER, SHOW VIEW priviledges.

	mysql> GRANT LOCK TABLES, SELECT, FILE, RELOAD, SUPER, SHOW VIEW ON lportal.* \
	    TO dba-backup@'localhost' IDENTIFIED BY 'mypassword';

## Usage

	backup_liferay.pl options
		
	  -?, --help			display this help-screen and exit
	  -u, --user=#			user for database login if not current user
	  -p, --password=#		password to use when connecting to server (if not set
							in my.cnf, which is recommended)
	  -d, --database=#		database name
	  -h, --host=#			hostname for local server when connecting over TCP/IP
	  -P, --port=#			port to use when connecting to local server with TCP/IP
	  -S, --socket=#		socket to use when connecting to local server

	  --lvm-volume-path <path>
							Path to the lvm volume where Liferay data is located
							For example /dev/vg0/opt
	  --lvm-snapshot-volume-path <path>
							Path to the lvm volume snapshot after it's created by
							lvcreate. For example /dev/vg0/opt-snapshot
	  --lvm-snapshot-volume-name <name>
							Snapshot volume name. For example opt-snapshot
	  --snapshot-mount-path <path>
							Path where snapshot volume will be mounted. 
							For example /mnt/opt-snapshot
	  --source-path <path>
							Path for Liferay data directory relative to mount
							point. For example /liferay-portal-6.1.0/data
	  --db-target-path <path>
							Path where database dump will be stored. For example
							/backup/mysql/lportal.sql
	  --data-target-path <path>
							Path where Liferay data will be backed up. For example
							/backup/liferay
	  --backup-method [tar|rsync]
							Use either rsync or tar to backup. Default is rsync
	  -c, --compress		Compress database backup and data backup if tar is used

	  -v, --verbose			verbose logging
	  -q, --quiet			run quietly without verbose logging

## Example

	backup_liferay.pl -u dba-backup -p <mypassword> -d lportal -h localhost \
		--lvm-volume-path /dev/vg0/opt --lvm-snapshot-volume-path /dev/vg0/opt-snapshot \
		--lvm-snapshot-volume-name opt-snapshot --lvm-snapshot-volume-size 50G \
		--snapshot-mount-path /backups/snapshot --source-path /liferay-portal-6.1.0/data/document_library \
		--db-target-path /backups/mysql/lportal.sql.gz --data-target-path /backups/liferay --compress

