#!/usr/bin/perl -w

use strict;
use T2::Schema;
use JavaScript::Dumper;

my $site = shift || die "Usage: $0 sitename";

my $schema = T2::Schema->read($site)
    or die "Couldn't load schema dump; have you run migrate_db.pl?";

# I found that Apache treats internal redirects differently if they
# start with "/var".  So, I have selected a name which does not
# conflict with Apache's bizarre and arbitrary handling of relative
# URLs
use constant DIR => "apachesux/lib/js";

system("mkdir -p ${\(DIR)} 2>/dev/null");

for my $class ( $schema->classes ) {

   # This only works because all of the classes are loaded - consider
   # this a FIXME, although all you'd need to do to avoid it would be
   # to have a generator floating about.
   my $prototype = JavaScript::Dumper::pkgname($class->name).".js";

   my ($basename) = ($prototype =~ m{(.*)/});
   if ($basename) {
	$basename = DIR."/".$basename;
	( -d $basename ) || (system("mkdir -p $basename") == 0)
            or die "mkdir failed";
   }

   if ( -f $prototype ) {
       rename $prototype, $prototype.".old";
   }

   print "Writing $prototype\n";
   open MODULE, ">${\(DIR)}/$prototype" or die $!;
   print MODULE $class->as_prototype;
   close MODULE;

}
