#!/usr/bin/perl -w
#
#  setup-schemadb.pl - creates the Schema database
#
# To use this script, first create etc/schema.dsn

use strict;

BEGIN { ( -d "lib" ) || (chdir ".."); die unless -d "lib" }
use lib "lib";

use Tangram;
use Tangram::mysql;
use DBI;

use T2::Schema;
use T2::Storage;

my @dsn = T2::Storage::get_dsn_info("schema", 1);
my @now = localtime(time());

my $backup = sprintf("schema-%.4d-%.2d-%.2d-%.2d:%.2d:%.2d", $now[5]+1900, $now[4]+1, @now[3,2,1,0]);

( -d "var/lib/backup" ) || (system("mkdir -p var/lib/backup") == 0)
    || die "Can't create var/lib/backup; $!";

$| = 1;
print "Backing up old database if present... ";
if (system("mysqldump -u$dsn[1] -p$dsn[2] schema"
	   .">var/lib/backup/$backup") == 0) {
    print "done\n";
    system("mysqladmin -u$dsn[1] -p$dsn[2] drop schema");
} else {
    print "no\n";
    unlink "var/lib/backup/$backup";
}

system("mysqladmin -u$dsn[1] -p$dsn[2] create schema");

print "Connecting to the database\n";
my $dbh = DBI->connect(@dsn) or die $DBI::errstr;

print "Creating tables with SQL command:\n";
Tangram::mysql->deploy(T2::Schema->schema);

print "Now creating tables...\n";
Tangram::mysql->deploy(T2::Schema->schema, @dsn);

print "Disconnecting from database\n";
$dbh->disconnect or die $DBI::errstr;

