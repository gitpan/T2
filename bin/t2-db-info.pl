#!/usr/bin/perl -w
#
# This script uses the etc/*.dsn files to return environment variables
# useful for other shell scripts in this package
#

use strict;

BEGIN { ( -d "lib" ) || (chdir ".."); die unless -d "lib" }
use lib "lib";

use T2::Storage;

my $site = (shift) || ( ( sort { $a cmp $b }
			  grep !/^schema$/,
			  map { s{.*/(.*)\.dsn$}{$1}; $_ }
			  <etc/*.dsn> ) [0] )
    || "schema";

my ($dsn, $username, $auth)
    = T2::Storage::get_dsn_info($site, "no_schema")
    or die "Could not load DSN info for site `$site'";

my ($host, $database);

($dsn =~ m/host=(\w+)/)     && ($host = $1);
($dsn =~ m/database=(\w+)/) && ($database = $1);

$host ||= "localhost";
$database ||= "schema";

print <<EOF;
SITE=$site
MYSQL_HOST=$host
MYSQL_DB=$database
MYSQL_USER=$username
MYSQL_AUTH=$auth
EOF

