#!/usr/bin/perl -w
#
# migrate_db.pl - deploy the DataBase schema to a new database,
#                 migrate the old database via MySQLDiff, and then
#                 dump the database schema to a Storable 2.07+
#                 structure.
#
# Limitations: this has only been tested on MySQL.  In fact, MySQLDiff
# would probably need to be ported to another DB to be able to switch.

BEGIN {
    ( -d "lib" ) || (chdir "..");
    die "run from inside the webroot" unless -d "lib";
}

use strict;
use lib "lib";

use Tangram;
use Tangram::mysql;
use DBI;
use T2::Schema;
use T2::Storage;
use Storable 2.06 qw(freeze thaw);
use Getopt::Long;

use constant PROGNAME => ($0 =~ m{([^/]*)$});
use constant VERSION => ('$Revision: 0.1$' =~ m{(\d+(?:\.\d+)*)$});

#---------------------------------------------------------------------
#  program message output functions
#---------------------------------------------------------------------
use vars qw($VERBOSITY);

sub abort {
    say("aborting: @_") if @_;
    print STDERR
	("Usage: ${\(PROGNAME)} [options] site\n",
	 "Try `${\(PROGNAME)} --help' for more information\n",
	);
    exit(1)
}
sub say   { print STDERR PROGNAME.": @_\n" }
sub barf  { say("ERROR:", @_); exit(1); }
sub moan  { say("WARNING:", @_) if ($VERBOSITY >= 0); }
sub remark { say("note:", @_) if ($VERBOSITY >= 1) }
sub mutter  { say(@_) if ($VERBOSITY >= 1) }
sub whisper { say(@_) if ($VERBOSITY >= 2) }
sub think   { say(@_) if ($VERBOSITY >= 3) }

#---------------------------------------------------------------------
#  set_defaults
#
#  configure default operation of the program based on PROGNAME
#---------------------------------------------------------------------
sub set_defaults {

    return (1, 0, 0, 1, 1) if ( PROGNAME =~ /\b migrate \b/x );
    return (1, 0, 0, 1, 0) if ( PROGNAME =~ /\b dump    \b/x );
    return (0, 0, 1, 0, 0) if ( PROGNAME =~ /\b undump  \b/x );
    return (0, 1, 0, 0, 0) if ( PROGNAME =~ /\b deploy  \b/x );
    return (0, 0, 0, 0, 0) if ( PROGNAME =~ /\b read    \b/x );

    return;
}

#---------------------------------------------------------------------
#  load_schema($site, $completely)
#
# Loads a T2 Schema structure.
#
# If $completely is true, it then uses `prefetch' and `traverse' to
# make sure that there are absolutely no on-demand paging references
# left.
#
# This whole function should be considered a massive FIXME :-)
#---------------------------------------------------------------------
sub load_schema {
    my $site = shift;
    my $do_prefetch = shift;

    say "loading schema for $site from schema DB";

    mutter "opening schema DB";
    my $schema_db = T2::Storage->open("schema")
	or barf "failed to connect to schema DB; $DBI::errstr";

    whisper "loading schema object";
    my $schema = T2::Schema->load($site, $schema_db);

    mutter "pre-selecting objects";
    my ($r_schema, $r_class, $r_attribute, $r_association, $r_method)
	= $schema_db->remote(qw(T2::Schema T2::Class T2::Attribute
				T2::Association T2::Method));
    my ($filter1, $filter2);
    whisper "loading T2::Class objects";
    my @classes = $schema_db->select
	(
	 $r_class,
	 filter => (
		    $filter1 =
		    ( $r_schema->{classes}->includes($r_class) &
		      ($filter2 = ($r_schema == $schema)) ) )
	);
    # It would rock if this prefetching was automatic for one to many
    # associations...
    if ($do_prefetch) {
	local($Tangram::TRACE) = \*STDOUT if ($VERBOSITY >= 4);
	think "pre-fetching Schema.classes";
	$schema_db->prefetch($r_schema => "classes", $filter2);
	think "pre-fetching Class.schema";
	$schema_db->prefetch($r_class  => "schema", $filter1);
	think "pre-fetching Class.superclass";
	$schema_db->prefetch($r_class  => "superclass", $filter1);
	think "pre-fetching Class.subclasses";
	$schema_db->prefetch($r_class  => "subclasses", $filter1);
    }
    mutter @classes." Classes";

    whisper "loading T2::Attribute objects";
    my @attribs = $schema_db->select
	(
	 $r_attribute,
	 filter => ($filter2 =
		    ( $r_class->{attributes}->includes($r_attribute) &
		      ($filter1 = ($r_class->{schema} == $schema)) ) )
	);
    if ($do_prefetch) {
	think "pre-fetching Class.attributes";
	$schema_db->prefetch($r_class => "attributes", $filter1);
	think "pre-fetching Attribute.class";
	$schema_db->prefetch($r_attribute => "class", $filter2);
	think "pre-fetching Attribute.options";
	$schema_db->prefetch($r_attribute => "options", $filter2);
    }
    mutter @attribs." Attributes";

    whisper "loading T2::Method objects";
    my @methods = $schema_db->select
	(
	 $r_method,
	 filter => ($filter2 =
		    ( $r_class->{methods}->includes($r_method) &
		      ($filter1 = ( $r_class->{schema} == $schema ))) )
	);
    if ($do_prefetch) {
	think "pre-fetching Class.methods";
	$schema_db->prefetch($r_class => "methods", $filter1);
	think "pre-fetching Method.class";
	$schema_db->prefetch($r_method => "class", $filter2);
    }
    mutter @methods." Methods";

    whisper "Loading T2::Association objects";
    my @assocs = $schema_db->select
	(
	 $r_association,
	 filter => ($filter2 =
		    ( $r_class->{associations}->includes($r_association) &
		      ($filter1 = ($r_class->{schema} == $schema ))) )
	);
    if ($do_prefetch) {
	think "pre-fetching Class.associations";
	$schema_db->prefetch($r_class => "associations", $filter1);
	think "pre-fetching Class.rev_assocs";
	$schema_db->prefetch($r_class => "rev_assocs", $filter2);
	think "pre-fetching Association.class";
	$schema_db->prefetch($r_association => "class", $filter2);
	think "pre-fetching Association.dest";
	$schema_db->prefetch($r_association => "dest", $filter2);
	think "pre-fetching Association.options";
	$schema_db->prefetch($r_association => "options", $filter2);
    }
    mutter @assocs." Associations";

    # No longer a major deficiency in Tangram! dB-)
    mutter "traversing memory structure";
    local($Tangram::TRACE)=\*STDERR if ($VERBOSITY > 1);
    $schema->traverse(sub {
			  mutter "Checking $_[0]";
			  while (my $key = each %{ $_[0] }) {
			      say "$_[0] : $key still tied!"
				  if tied $_[0]->{$key};
			  }
		      });

    return ($schema, $schema_db);
}

#---------------------------------------------------------------------
#  get_dsn_2($site) : ($dsn, $user, $password, $host, $db);
#
# Gets the DSN information for a site, but extracts the database host
# and DB name from the DSN field.
#---------------------------------------------------------------------
sub get_dsn_2 {
    my $site = shift;
    my ($user, $password, $host, $db);

    whisper "loading DSN information for site $site";
    my @dsn = T2::Storage::get_dsn_info($site, 1);
    ($db) = ($dsn[0] =~ m/database\s*=\s*([^\s;]*)/);
    ($host) = ($dsn[0] =~ m/host\s*=\s*([^\s;]*)/);
    $db ||= $site;

    $user = $dsn[1] || "";
    $password = $dsn[2];
    $host ||= "";

    return ($dsn[0], $user, $password, $host, $db);
}

#---------------------------------------------------------------------
#  mysql_drop_n_add_db($host, $db, $user, $password)
#
# DROP DATABASE $db
# CREATE DATABASE $db
#
# Use with caution :-)
#---------------------------------------------------------------------
sub mysql_drop_n_add_db {
    my ($host, $db, $user, $password) = (@_);

    mutter "dropping database ${db}";

    my $args = join " ", (
			  ($host     ? "-h$host"     : ()),
			  ($password ? "-p$password" : ()),
			  ($user     ? "-u$user"     : ()),
			 );

    # drop the old database if it exists
    system("yes | mysqladmin $args drop ${db} >/dev/null 2>&1")
	if (system("mysqldump $args ${db} >/dev/null 2>&1") == 0);

    mutter "creating database ${db}";
    system("mysqladmin $args create ${db}");

}

#---------------------------------------------------------------------
#  dump_schema($schema, $filename)
#
# Dumps the passed schema to $filename, assumes that there are already
# no on-demand references left in the structure (Storable freezes them
# too! :-))
#---------------------------------------------------------------------
sub dump_schema {
    my $schema = shift;
    my $filename = shift;
    my $c = 1;

    if ( -f $filename ) {
	while ( -f $filename.".$c" ) { $c ++ }
	mutter "linking old dump $filename to $filename.$c";
	link($filename, $filename.".$c")
	    or die "link(${filename}{,.$c}) failed; $!";
    }

    open DUMP, ">$filename"
	or die "open of $filename for writing failed; $!";

    binmode DUMP;
    eval {
	$schema->set_storage(undef);
	local($Storable::Deparse);
	$Storable::Deparse = 1;
	$Storable::forgive_me = 0;
	$Storable::DEBUGME = $Storable::DEBUGME = 0;
	whisper "go, go, gadget Storable ;-)";
	print DUMP freeze $schema;
	whisper "wahey!  Storable did it!";
    };
    close DUMP;
    moan "dump to $filename failed; $@" if $@;
}

#---------------------------------------------------------------------
#  help
#---------------------------------------------------------------------
sub help {
    print &version;
    print STDERR version(), <<EOF;

This script is used to manage rolling out and migrating Tangram
database stores, as well as converting `schema' structures to an from
various formats.  Many of the t2-*.pl scripts are convenience aliases
for this script.

It operates in three phases.  First, the schema is loaded from either
a database, or a `Storable' dump (required, mutually exclusive
options):

  -l, --load        Load the schema structure for the schema being
                    operated on from the `schema' T2 store
                    (default for `dump' and `migrate' scripts)
  -r, --read        Read the schema from the Storable file etc/foo.t2
                    (default for `undump', `deploy' and `read'
                    scripts)

It can then write it out to various formats:

  --dump-tangram    Dump to STDOUT as a Data::Dumper compatible
                    Tangram::Schema input data structure.  For
                    debugging only for now.
  --dump            Dump the schema to Storable file etc/foo.t2
                    (default for `dump', `migrate' scripts)
  --no-dump         Cancel `dump' action of `migrate'
  --undump          Insert a read Schema to the `schema' T2 store.
  --no-undump       Cancel `undump' action of `undump' script

Deploy to a T2 store, or upgrade an existing T2 store to this schema
(note: migration is performed with the mysqldiff(1) utility):

  --deploy          Write out database to a freshly created, empty
                    database (default for `deploy' script)
  --no-deploy       Cancel `deploy' action of t2-deploy-db.pl

  --migrate         Upgrade an existing database, by deploying to an
                    empty, freshly created database called \${db}_new,
                    where \${db} is the name of the database in the
                    DSN file.
  --no-migrate      Cancel `migrate' action of t2-migrate-db.pl

Currently, this script is heavily dependant on MySQL - as `mysqldiff'
only exists for MySQL.  Patches to provide support for other databases
more than welcome.
EOF
    exit(0);
}
sub version {
    "This is ${\(PROGNAME)}, version ${\(VERSION)}\n";
}

#=====================================================================
#   MAIN SECTION STARTS HERE
#=====================================================================
my ($site, $force, $schema, $schema_storage, $db, $filename);
my ($do_load, $do_deploy, $do_undump, $do_dump, $do_migrate)
    = set_defaults()
    or die "t2-migrate-db.pl: $0 bad";

my $do_dump_tangram;

$VERBOSITY = 0;                                            ( $| = 1 );

Getopt::Long::config("bundling");
Getopt::Long::GetOptions
    (
     'help|h' => \&help,
     'verbose|v' => sub { $VERBOSITY++ },
     'version' => sub { print version; exit },
     'debug|D' => sub { $VERBOSITY+=2 },
     'database|d=s' => \$db,
     'force-load|F' => \$force,
     'load|l' => \$do_load,
     'read|r' => sub { $do_load = 0 },
     'deploy' => sub { $do_deploy = 1 },
     'no-deploy' => sub { $do_deploy = 0 },
     'dump' => sub { $do_dump = 1 },
     'no-dump' => sub { $do_dump = 0 },
     'undump' => sub { $do_undump = 1 },
     'no-undump' => sub { $do_undump = 0 },
     'migrate' => sub { $do_migrate = 1 },
     'no-migrate' => sub { $do_migrate = 0 },
     'dump-tangram' => \$do_dump_tangram,
     'output|o=s' => \$filename,
    );

# Find out what we're operating on
$site = shift or abort "no site name given";
abort "unknown arguments: @ARGV" if @ARGV;

(my ($dsn, $user, $password, $host), $db) = get_dsn_2($site);
mutter("T2 source ".$site." is at mysql://".($user?$user.'@':"")
       .($host||"(localsock)")."/$db");

# Phase 1. get the schema - load it completely, or read it.  There is
# a `hack' for the T2::Schema structures, for which it would not make
# sense to use any other version than the version in this module.
if ($site eq "schema" and not $force) {
    say "using internal schema structure";
    $schema = $T2::Schema::class_obj;
} elsif ($do_load) {
    ($schema, $schema_storage)
	= load_schema($site, ($do_dump || $do_undump));
} else {
    mutter "reading schema from dump";
    $schema = T2::Schema->read($site);
}

say "T2 Schema `$site': ".$schema->classes_size." classes";
if ($VERBOSITY > 1) {
    say "Classes: ".join(", ", map { $_->name } $schema->classes);
}

# Stage 1b.  Show
if ($do_dump_tangram) {
    eval "use Data::Dumper"; die $@ if $@;
    print Dumper($schema->schema_raw);
}

# Stage 2.  Dump
if ($do_dump) {

    $filename ||= "etc/".$schema->site_name.".t2";
    say "dumping schema structure to $filename via Storable";

    dump_schema($schema, $filename);

} elsif ($do_undump) {

    $schema_storage ||= T2::Storage->open("schema");

    $schema->set_classes(grep { defined } $schema->classes);
    say("inserting schema for `$site' into the database");
    $schema_storage->insert($schema);

}

# Step 3a. Deploy
if ($do_deploy) {

    say "deploying site $site";
    mutter "connecting to the ${db} database";
    my $dbh = DBI->connect($dsn, $user, $password)
	or abort "DB connection failed; $DBI::errstr";

    if ($VERBOSITY > 1) {
	say "creating tables with SQL command:";
	Tangram::mysql->deploy($schema->schema);
    }

    mutter "creating tables in ${db}";
    Tangram::mysql->deploy($schema->schema, $dsn, $user, $password);

    whisper "disconnecting from database";
    $dbh->disconnect
	or die $DBI::errstr;

}

# Action 3b. Migrate
elsif ($do_migrate) {

    say "commencing schema migration";

    # Operate on the _new database only
    $dsn =~ s/${db}/${db}_new/ or abort "no DB name in DSN (`$dsn')";
    $db .= "_new";

    mysql_drop_n_add_db($host, $db, $user, $password);

    # Reset the ${db}_new database
    mutter "connecting to the ${db} database";
    my $dbh = DBI->connect($dsn, $user, $password)
	or abort "DB connection failed; $DBI::errstr";

    if ($VERBOSITY > 1) {
	say "creating tables with SQL command:";
	Tangram::mysql->deploy($schema->schema);
    }

    mutter "creating tables in ${db}";
    Tangram::mysql->deploy($schema->schema, $dsn, $user, $password);

    whisper "disconnecting from database";
    $dbh->disconnect
	or die $DBI::errstr;

    say("Running MySQL diff - CHECK THE ALTER TABLE COMMANDS FOR "
	."SANITY");
    $db =~ s{_new}{};
    $host =~ s{^}{-h=};
    $user =~ s{^}{-u=};
    $password =~ s{^}{-p=};
    system("mysqldiff -A $host $user $password ${db} ${db}_new");

}



