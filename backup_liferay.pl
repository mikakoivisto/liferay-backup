#!/usr/bin/perl

# Copyright (c) 2012 Mika Koivisto <mika@javaguru.fi>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.	If not, see <http://www.gnu.org/licenses/>.

use strict;
use Getopt::Long;
use DBI;
use POSIX qw(strftime);

my $VERSION = "0.1";

my $OPTIONS = <<"_OPTIONS";

$0 Ver $VERSION Copyright (C) 2012 Mika Koivisto
This program comes with ABSOLUTELY NO WARRANTY; 
This is free software, and you are welcome to
redistribute it under certain conditions;
See the GNU General Public License for more details.

Usage: $0 

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
_OPTIONS

my ($lvmVolPath, $lvmSnapshotVolPath, $lvmSnapshotVolName, $lvmSnapshotVolSize,
	$snapshotMountPath, $sourcePath, $dbTargetPath, $dataTargetPath,
	$backupMethod, $quiet, $verbose, $compress);

sub usage {
	die @_, $OPTIONS;
}

sub logwrite {
	print STDOUT strftime("%m/%d/%y %H:%M",localtime(time)). " " . join(" ", @_) . "\n";
}

sub loginfo {
   logwrite(@_) if $verbose;
}

sub logerr {
   print STDERR strftime("%m/%d/%y %H:%M",localtime(time)). " " . join(" ", @_) . "\n";
}

sub logdie {
   die(strftime("%m/%d/%y %H:%M",localtime(time)). " " . join(" ", @_) . "\n");
}

sub runcmd {
	logwrite("Running:", @_) if $verbose;
	return system(@_);
}

my %opt = (
);

$backupMethod = "rsync";

Getopt::Long::Configure(qw(no_ignore_case));
GetOptions( \%opt,
	"help",
	"host|h=s",
	"user|u=s",
	"password|p=s",
	"port|P=s",
	"socket|S=s",
	"database|d=s",
	"lvm-volume-path|=s" => \$lvmVolPath,
	"lvm-snapshot-volume-path|=s" => \$lvmSnapshotVolPath,
	"lvm-snapshot-volume-name|=s" => \$lvmSnapshotVolName,
	"lvm-snapshot-volume-size|=s" => \$lvmSnapshotVolSize,
	"snapshot-mount-path|=s" => \$snapshotMountPath,
	"source-path|=s" => \$sourcePath,
	"db-target-path|=s" => \$dbTargetPath,
	"data-target-path|=s" => \$dataTargetPath,
	"backup-method|:s" => \$backupMethod,
	"quiet|q" => \$quiet,
	"verbose|v" => \$verbose,
	"compress|c" => \$compress,
) or usage ();

usage("") if ($opt{help});

if ($verbose) {
	loginfo("lvm volume path: $lvmVolPath");
	loginfo("lvm snapshot volume path: $lvmSnapshotVolPath");
	loginfo("lvm snapshot volume name: $lvmSnapshotVolName");
	loginfo("snapshot mount path: $snapshotMountPath");
	loginfo("source path: $sourcePath");
	loginfo("db target path: $dbTargetPath");
	loginfo("data target path: $dataTargetPath");
	loginfo("backup method: $backupMethod");
	loginfo("compress: " . ($compress ? "enabled" : "disabled"));
}

# --- connect to the database ---
my $dsn;
$dsn  = ";host=" . (defined($opt{host}) ? $opt{host} : "localhost");
$dsn .= ";port=$opt{port}" if $opt{port};
$dsn .= ";mysql_socket=$opt{socket}" if $opt{socket};

# use mysql_read_default_group=liferaybackup so that [client] and
# [liferaybackup] groups will be read from standard options files.

my $data_source = "dbi:mysql:$opt{database}$dsn;mysql_read_default_group=liferaybackup";

loginfo("Connecting to database with datasource $opt{database}$dsn; and user $opt{user}");

my $dbh = DBI->connect($data_source, $opt{user}, $opt{password},
{
	RaiseError => 1,
	PrintError => 0,
	AutoCommit => 1,
}) or logdie($@);

my $tables = $dbh->selectall_arrayref("show tables") || logdie "Error getting tables from database $opt{database}: $@";

my $locks = "";
foreach my $table (@$tables) {
	if ($locks eq '') {
		$locks = "$table->[0] READ";
	}
	else {
		$locks = "$locks, $table->[0] READ";
	}
}

loginfo("Locking tables: LOCK TABLES $locks");

$dbh->do("LOCK TABLES $locks") or logdie "Error can't lock tables: $@";

if ($compress) {
	runcmd("mysqldump -u $opt{user} --password=$opt{password} -h $opt{host} $opt{database} | gzip -9 > $dbTargetPath");
}
else {
	runcmd("mysqldump -u $opt{user} --password=$opt{password} -h $opt{host} $opt{database} > $dbTargetPath");
}

# Create snapshot
my $snapshotReturn = runcmd("lvcreate -L$lvmSnapshotVolSize -s -n $lvmSnapshotVolName $lvmVolPath");

logerr("Creating snapshot failed: $@") unless ($snapshotReturn == 0);

# Snaphshot is done unlock tables
loginfo("Unlocking tables: UNLOCK TABLES");

$dbh->do("UNLOCK TABLES") or logdie "Error can't unlock tables: $@";
$dbh->disconnect;

logdie("Terminating process due to failed snapshot.") unless ($snapshotReturn == 0);

runcmd("mount -o ro $lvmSnapshotVolPath $snapshotMountPath");

# Create backup

if ($backupMethod eq 'rsync') {
	my $rsyncOpts = "--delete -C";
	$rsyncOpts .= " -q" if ($quiet);
	$rsyncOpts .= " -v" if ($verbose);
	$rsyncOpts .= " -a -r";
	runcmd("rsync $rsyncOpts ${snapshotMountPath}${sourcePath} $dataTargetPath");
}
elsif ($backupMethod eq 'tar') {
	my $tarOpts = "-";
	$tarOpts .= "z" if ($compress); 
	$tarOpts .= "c";
	$tarOpts .= "v" if ($verbose);
	$tarOpts .= "f";
	runcmd("tar $tarOpts ${snapshotMountPath}${sourcePath} $dataTargetPath");
}

runcmd("umount $snapshotMountPath");
runcmd("lvremove -f $lvmSnapshotVolPath");
