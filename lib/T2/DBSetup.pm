
=head1 NAME

T2::DBSetup - deploy T2 store during Makefile.PL

=head1 SYNOPSIS

  # Example using traditional ExtUtils::MakeMaker
  use ExtUtils::MakeMaker;

  use lib "lib";
  eval "use T2::DBSetup";
  goto NOTESTS if $@;

  # get the schema for your project...
  eval "use T2::Schema";
  goto NOTESTS if $@;
  my $schema = $T2::Schema::class_obj;

  T2::DBSetup->deploy("site_name", $schema)
      or goto NOTESTS;

  print("Great, the database was deployed successfully, now"
       ."I can continue with my testing...\n");

  NOTESTS:
  # just spit out a Makefile, so that automatic
  # dependancies work.
  WriteMakefile
    (
     'PREREQ_PM'        => {
			    T2 => 0.08,
			   },
      ...
    );

=head1 DESCRIPTION

The T2::DBSetup module allows for easily writing test suites that
require a database to perform.

It prompts the user to provide database connection information, then
writes that information to a place that your scripts can easily
access.

=cut

package T2::DBSetup;

use Carp;

use Storable;
use T2::Storage;

sub yes
{
    return readlien((shift||"")."(Y/n)")
	=~ /^(Y(e(s)?)?|A(YE|II+!*))?\n?$/i;
}

sub yeah_no  # it's an antipodean thing
{
    return readlien((shift||"")."(N/y)")
	=~ /^(Y(e(s)?)?|A(YE|II+!*))\n?$/i;
}

our $term;

if ( -t STDIN ) {
    eval "use Term::ReadLine";
    unless ( $@ ) {
	$term = new Term::ReadLine "T2::DBSetup prompts";
    }
}

END {
    $term = undef;
}

sub readlien {
    my $prompt = shift;
    if ( $term ) {
	my $item = $term->readline($prompt) || "";
	$item =~ s{^\s+|\s+$}{}g;
	$term->addhistory($item) if ($item =~ m/\S/);
	return $item;
    } else {
	print $prompt;
	return <STDIN>
    }
}

sub deploy {
    shift if UNIVERSAL::isa($_[0], __PACKAGE__);

    my $site_name = shift
	or croak("No site_name given to ".__PACKAGE__."::deploy");

    my $schema = shift;
    UNIVERSAL::isa($schema, "T2::Schema")
	    or croak (__PACKAGE__."::deploy must be passed a "
		      ."T2::Schema object");

    print qq{
Do you plan to run the `$site_name' test suite ?
};

    return unless yes("(you will need to set up an empty database)");

    my $configured;

    if ($ENV{T2_DSN_SCHEMA})
	{
	    print qq{
You have set T2_DSN_SCHEMA to $ENV{T2_DSN_SCHEMA}.
};
	    $configured = yes("Should I use it (note: keep it there during test runs)?");
	}


    if (!$configured && -e "t/$site_name.dsn")
	{
	    system("cat t/$site_name.dsn");
	    print qq{

It looks like there is a 't/$site_name.dsn' file already (shown
above). It probably contains connection information from a previous
};
	    ($configured = yes("installation. Should I use it?"));
	}

    unless ($configured) {
	print qq{
Please create a test database (and, if you like, a `real' database),
and let me know the details to access it.

It is recommended that you name the test database `${site_name}_t'.
I must be able to create and drop tables in that database.

You would be well advised to create your `live' database at the same
time, so that you can create database accounts with identical access
rights and hence be sure that you are performing an accurate test.

Once you have created that, you need to supply me with a DBI
connection string; for instance, using mysql:

    dbi:mysql:database=${site_name}_t

See the DBI perldoc page (`perldoc DBI') for more information.

 };

	my $cs = readlien("Enter DBI connect string: ")
	    or do {
		print "OK, be like that then.  Skipping tests.\n";
		goto NOTESTS;
	    };
	chomp $cs;

	$cs = "dbi:$cs" unless $cs =~ /^dbi\:/i;

	my $user = readlien("Enter Database login name: ");
	chomp $user;

	my $passwd = readlien("Enter Database login password: ");
	chomp $passwd;

	print <<"MSG";

Thank you. I am going to save this information to 't/$site_name.dsn'.
If you have given sensitive information, make sure to destroy the file
when the tests have been completed.  Or, better, revise your network
infrastructure so that your database passwords are not sensitive... :)
MSG

	open CONFIG, ">t/$site_name.dsn"
	    or die "Cannot create 't/$site_name.dsn'; $!";
	if ( (print CONFIG <<EOF) &&
dsn $cs
user $user
auth $passwd
schema t/$site_name
EOF
	     (close CONFIG) ) {
	    print "Wrote t/$site_name.dsn successfully\n";
	} else {
	    print "Failed to write to t/$site_name.dsn; $!\n";
	}
    }

    # load the passwords, etc
    eval "use T2::Storage";

    print q{
Hmm, loading the T2::Storage module failed, do you have the
prerequisite modules installed?
}, goto NOTESTS if $@;

    my ($dsn, $user, $passwd)
	= T2::Storage::get_dsn_info("t/$site_name", 1);

    my $t2_file_ok;

    if ( -f "t/$site_name.t2" ) {
	print qq{
The compiled schema file t/$site_name.t2 exists.
};
	if (yes("Do you wish to use it ?")) {
	    $t2_file_ok = 1;
	}
    }

    if (!$t2_file_ok) {

	if ($dsn =~ m/:mysql:/i) {
	    print qq{
You have selected the mysql driver.  If you use the InnoDB table type,
you can have transactions - otherwise, you will have emulated (single
file) transactions.

Note; you will need to have the InnoDB table type compiled into your
MySQL server.  See the MySQL/InnoDB manual for more, starting from:

  http://www.mysql.com/doc/en/InnoDB.html

If the command "SHOW INNODB STATUS" works in the mysql utility, you
are safe.

If you're interested in being able to audit your application with the
binary database log, then you should also set your transaction
isolation level to SERIALIZABLE, see:

  http://www.mysql.com/doc/en/InnoDB_transaction_isolation.html

};
	    if (yeah_no("Use InnoDB tables")) {
		$schema->set_table_type("InnoDB");
	    }
	}

	local($Storable::Deparse);
	local($Storable::forgive_me);
	if ( $Storable::VERSION >= 2.07 ) {
	    $Storable::Deparse = 1;
	} else {
	    $Storable::forgive_me = 1;
	}

	print "\nNow writing the T2 Schema file for `$site_name'".
	    ($schema->version ? " version ".$schema->version : "")."\n";

	open SCHEMA, ">t/$site_name.t2"
	    or die "failed to open t/$site_name.t2 for writing; $!";
	if ( (binmode SCHEMA) &&
	     (print SCHEMA freeze $schema) &&
	     (close SCHEMA) ) {
	    print "Wrote t/$site_name.t2 successfully\n";
	} else {
	    print "Error writing t/$site_name.t2; $!";
	}
    }

    $SIG{SEGV} = "IGNORE";
#sub {
	#kill 2, $$;
	##print STDERR ("Caught a segfault - see README for more "
		      #."information.\n");
    #};

    print qq{
Reading the T2 schema from dump.  If this causes a segfault, read the
README in the T2 distribution, or see `perldoc T2::DBSetup'.
};
    (undef,undef,undef,$schema)
	= T2::Storage::get_dsn_info("t/$site_name");

    (my $tmp_passwd = $passwd) =~ s/./x/g;

    $passwd ||= "(no password)";

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

    die "No schema; probably t/$site_name.t2 wasn't written"
	    unless $schema;

    my $dbi_driver = (split ':', $dsn)[1];

    my $pkg = "Tangram::$dbi_driver";
    eval "use $pkg";
    $pkg = "Tangram::Relational" if $@;

    $schema = $schema->schema if $schema->isa("T2::Schema");

    if (my $dbh = DBI->connect( $dsn, $user, $passwd )) {

	do {
	    local $dbh->{PrintError};
	    $pkg->retreat($schema, $dbh);
	};

	$pkg->deploy($schema, $dbh);
	$dbh->disconnect;

	print q{Schema deployment successful!
};

	return $schema;

    } else {

	print STDERR "Failed to connect to the database; $DBI::errstr\n";
	goto NOTESTS;

    }

    NOTESTS:
    return undef;

}


1;

__END__

=head1 BUGS

All current versions of Storable have a bug which affects loading of
schema files.

See L<http://guest:guest@rt.perl.org/rt3/Ticket/Display.html?id=25145>
for the current status of this bug.

Usually, you can re-run the Makefile.PL, and the different random hash
seed chosen by Perl will prevent the segfault from occurring.

=cut
