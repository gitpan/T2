#!/usr/bin/perl -w

use Test::More tests => 4;

use strict;

BEGIN { ( -d "lib" ) || chdir ("..");
	( -d "lib" ) || die("where am i?"); }
use lib "var/lib/perl";
use lib "lib";

use_ok("T2::Schema");

use T2::Storage;

my $storage = T2::Storage->open("t/schema");

ok($storage && $storage->isa("T2::Storage"),
   "Connected to schema database");

my $schema = T2::Schema->load("schema", $storage);
ok($schema
   && $schema->isa("T2::Schema")
   && $schema->site_name eq "schema",
   "Loaded the schema site schema OK");

my $class = $schema->class("T2::Class");
is($class->associations_size, 7, "Class has seven associations");

