use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
use lib 'lib';

sub yes
{
    print ' (Y/n) ';
    my $resp = <STDIN>;
    if (defined $resp) {
	return $resp =~ /^(Y(e(s)?)?|A(YE|II+!*))?\n?$/i;
    } else {
	return;
    }
}

sub yeah_no  # it's an antipodean thing
{
    print ' (N/y) ';
    return <STDIN> =~ /^(Y(e(s)?)?|A(YE|II+!*))\n?$/i;

}

print q{Do you plan to run the test suite ?
(you will need to set up an empty database for the test suite)};

goto NOTESTS unless yes();

my $configured;

if ($ENV{T2_DSN_SCHEMA})
{
   print qq{
You have set T2_DSN_SCHEMA to $ENV{T2_DSN_SCHEMA}.
Should I use it?};
   $configured = yes();
}


if (!$configured && -e 't/schema.dsn')
{
   print q{
It looks like there is a 't/schema.dsn' file already. It probably
contains connection information from a previous installation. Should I
use it?};
   $configured = yes();
}

unless ($configured)
{
   print q{
Please give me the login and password for accessing the schema database.
I must be able to create and drop tables in that database.};

   print "\n1) DBI connect string (omit the \'DBI:\' part): ";
   my $cs = <STDIN>;
   chop $cs;

   $cs = "dbi:$cs" unless $cs =~ /^dbi\:/i;

   my $table_type;

   if ($cs =~ m/:mysql:/i) {
       print q{Use InnoDB tables};
       if (yeah_no()) {
	   $table_type = "InnoDB";
       }
   }

   print "2) Login: ";
   my $user = <STDIN>;
   chop $user;

   print "3) Password: ";
   my $passwd = <STDIN>;
   chop $passwd;

   print <<'MSG';

Thank you. I am going to save this information to 't/schema.dsn'.
If you have given me sensitive information, make sure to destroy
the file when the tests have been completed.
MSG

   open CONFIG, '>t/schema.dsn'
       or die "Cannot create 't/schema.dsn'; $!";

   print CONFIG <<EOF;
dsn $cs
user $user
auth $passwd
schema use T2::Schema; T2::Schema->schema
EOF
   close CONFIG;
}

{
    eval "use T2::Storage";

    print q{
Hmm, loading the T2::Storage module failed, do you have the
prerequisite modules installed?
}, goto NOTESTS if $@;

    my ($dsn, $user, $passwd, $schema)
	= T2::Storage::get_dsn_info("t/schema");

    (my $tmp_passwd = $passwd) =~ s/./x/g;
    print qq{
Now I will attempt to connect and prepare the database at:

 dsn:    $dsn
 user:   $user
 passwd: $tmp_passwd

If there is anything there already IT WILL BE REMOVED.
};
    if ($dsn =~ m/_t\b/) {

	print q{
Ah, your DSN contains "_t", you must know about this.  Going ahead.
};

    } else {

	print q{
Do NOT use the same database for this test suite as the one you use to
store your normal schemas.

Proceed};

	goto NOTESTS unless yeah_no;
    }


    if (my $dbh = DBI->connect( $dsn, $user, $passwd )) {

	do {
	    local $dbh->{PrintError};
            Tangram::Relational->retreat($schema, $dbh);
	};

	Tangram::Relational->deploy($schema, $dbh);
	$dbh->disconnect;

	print q{Schema deployment successful!
Use `make test' to run the test suite.
};

    } else {

	print STDERR "Failed to connect to the database; $DBI::errstr\n";
	goto NOTESTS;

    }
}

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


