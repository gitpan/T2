#!/usr/bin/perl -w

use Test::More skip_all => "Test suite unfinished";

use strict;

BEGIN { ( -d "lib" ) || chdir ("..");
	( -d "lib" ) || die("where am i?"); }
use lib "var/lib/perl";
use lib "lib";

use_ok("T2::Schema");

my $schema = T2::Schema->read("schema");
isa_ok($schema, "T2::Schema", "read schema object");

is($schema->classes(0)->name, "T2::Class", "Schema object sane");


