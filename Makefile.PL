use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
use lib 'lib';

eval "use T2::DBSetup";
warn $@, goto NOTESTS if $@;

# get the schema for your project...
eval "use T2::Schema";
warn $@, goto NOTESTS if $@;

my $schema = $T2::Schema::class_obj;

T2::DBSetup->deploy("T2", $schema)
    or goto NOTESTS;

print("Use `make test' to run the test suite.\n");

NOTESTS:

WriteMakefile
    (
     'NAME'		=> "T2",
     'PREREQ_PM'        => {
			    Set::Object => 1.04,
			    Class::Tangram => 1.54,
			    Tangram => 2.07,
			    "Test::More" => 0,
			    DBI => 0,
			   },
     'VERSION_FROM'     => "lib/T2.pm",
     'EXE_FILES'	=> [ <bin/*.pl> ],
     ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT         => "Object Relational mapping/persistence system",
       AUTHOR           => "Sam Vilain <samv@cpan.org>") : ()),
    );


