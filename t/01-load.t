# -*- perl -*-

# t/001_load.t - check module loading and create testing directory

use Test::More tests => 3;

BEGIN { use_ok( 'T2::Schema' ); }

my $object = T2::Schema->new ();
isa_ok ($object, 'T2::Schema');

use_ok("T2::Storage");

# what do we need to test?

# Schemas could come from various places;

#   1. From a single T2::Schema structure (see 02-native.t)
#   2. From a Tangram::Schema data structure (see 03-tangram.t)
#   3. From a set of Class::Tangram source files (see
#      04-class-tangram.t)

