#!/usr/bin/perl -w

use Test::More skip_all => "Test suite not written yet";

use strict;

BEGIN { ( -d "lib" ) || chdir ("..");
	( -d "lib" ) || die("where am i?"); }

use lib "lib";

# This tests tests importing an entire Tangram::Schema structure,
# like, for instance, Springfield, then writing it to a dump.

