#!/usr/bin/perl -w
#
#  diff_schemadb.pl - investigating use of mysqldiff for schema migration
#

BEGIN {
    ( -d "lib" ) || (chdir "..");
    die unless -d "lib";
}

use strict;
use lib "var/lib/perl";
use lib "lib";

use Tangram;
use Tangram::mysql;
use DBI;

use Schema;
use T2::Storage;

my $db = shift||"schema";

my @dsn = T2::Storage::get_dsn_info($db, 1);

my @now = localtime(time());

my $backup = sprintf("var/lib/backup/$db-%.4d-%.2d-%.2d-%.2d:%.2d:%.2d", $now[5]+1900, $now[4]+1, @now[3,2,1,0]);

if (system("mysqldump -u$dsn[1] -p$dsn[2] ${db}_new > /dev/null") == 0) {
    system("mysqladmin -u$dsn[1] -p$dsn[2] drop ${db}_new");
}

system("mysqladmin -u$dsn[1] -p$dsn[2] create ${db}_new");

$dsn[0] =~ s/${db}/${db}_new/;

print "Connecting to the database\n";
my $dbh = DBI->connect(@dsn)
    or die $DBI::errstr;

my $schema = Schema->load($db);
print "Creating tables with SQL command:\n";
Tangram::mysql->deploy($schema->schema);

print "Now creating tables...\n";
Tangram::mysql->deploy($schema->schema, @dsn);

print "Disconnecting from database\n";
$dbh->disconnect
    or die $DBI::errstr;

print "Diff'ing\n";
system("mysqldiff -A -u=$dsn[1] -p=$dsn[2] ${db} ${db}_new");

