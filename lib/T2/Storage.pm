#    -*- cperl -*-

=head1 NAME

T2::Storage - Database handle, object cache

=head1 SYNOPSIS

  # load the application schema, connect to the database
  my $storage = T2::Storage->open("MyApp");

  # store an object with a schema
  $storage->insert($object);

=head1 DESCRIPTION

The Tangram T2 Storage class.  Currently, this is a subclass of
Tangram::Storage, but it is planned to slowly move pieces of Tangram
proper into this new core.

=cut

package T2::Storage;

use strict 'vars', 'subs';
use Tangram;
use Tangram::FlatArray;
use Carp;

use Tangram::Storage;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Tangram::Storage);
@EXPORT_OK = qw(@ISA);

=head1 METHODS

=over

=item B<T2::Storage-E<gt>open($site, $schema)>

This function opens a connection to a named database source.  It takes
between one and two parameters:

=over

=item B<$site>

The `site' to connect to.  This is a named data source, a bit like
using ODBC but stored in a text file rather than an opaque registry.
This should correspond to a file in F<etc/> called F<$site.dsn>, as
extracted by C<T2::Storage::get_dsn_info> (see L<get_dsn_info>).

=item B<$schema>

This should be either a Tangram::Schema object, or a T2::Schema
object.

=back

=cut

sub open ($$;$) {
    my ($class, $site_name, $schema) = (@_);

    my @dsn = get_dsn_info($site_name, $schema);
    $schema ||= pop @dsn;

    die "can't get a schema for $site_name"
	unless ($schema and ($schema->isa("Tangram::Schema") ||
			     $schema->isa("T2::Schema")));

    $schema = $schema->schema if $schema->isa("T2::Schema");

    my $dbi_driver = (split ':', $dsn[0])[1];
    my $tangram_d = "Tangram::$dbi_driver";
    my $self;

    local $SIG{__DIE__} = sub { $@ = $_[0] };
    eval "use $tangram_d";
    if ( $@ ) {
	# connect to the database
	$self = $class->SUPER::connect($schema, @dsn)
	    or die $DBI::errstr;
    } else {
	my $t2_storage = "T2::Storage::$dbi_driver";
	unless ( keys %{"${t2_storage}::"}) {
	    @{"${t2_storage}::ISA"}
		= ("Tangram::${dbi_driver}::Storage",
		   "T2::Storage");
	}
	$self = $t2_storage->connect($schema, @dsn)
	    or die $DBI::errstr;
    }

    # setup the object and return
    $self->{site_name} = $site_name;

    return $self;
}

=over get_dsn_info($site_name, $dont_get_schema)

Gets the database information for B<$site_name>, in the form ($dsn,
$username, $password, $schema); If $dont_get_schema is set, no attempt
to load the Tangram schema is made.

=cut

use Scalar::Util qw(blessed);

our @dsn_path = qw(. etc ../etc);

sub get_dsn_info {
    my $self;
    if (blessed $_[0] and $_[0]->isa(__PACKAGE__)) {
	$self = shift;
    }
    my ($site_name, $dont_get_schema) = (@_);
    $site_name ||= $self->{site_name} if $self;

    # read in the DSN info
    my $dsn_file;
    for my $path (@dsn_path) {
	( -f ($dsn_file = "$path/${site_name}.dsn")) && last;
    }
    CORE::open DSN, "<$dsn_file"
	or die ("Failed to load site DSN configuration file "
		."${site_name}.dsn (search path: @dsn_path); $!");
    my ($dsn, $username, $auth, $schema_eval);
    while (<DSN>) {
	chomp;
	m/^\s*dsn\s+\b(.*?)\s*$/ && ($dsn = $1);
	m/^\s*user\s+\b(.*?)\s*$/ && ($username = $1);
	m/^\s*auth\s+\b(.*?)\s*$/ && ($auth = $1);
	m/^\s*schema\s+\b(.*?)\s*$/ && ($schema_eval = $1);
    }
    close DSN;

    if ($dont_get_schema) {
	return ($dsn, $username, $auth);
    } else {
	#no strict;
	# get schema - try to avoid this string eval
	eval "use T2::Schema" unless $INC{"T2/Schema.pm"};
	my $schema = eval $schema_eval;
	if ($@) {
	    $schema = T2::Schema->read($schema_eval);
	}
	return ($dsn, $username, $auth, $schema);
    }
}

=over B<$storage-E<gt>site_name>

Returns the site name that was used to connect to this database.

=cut

sub site_name($) {
    my ($self) = (@_);
    $self->isa("T2::Storage") or die "type mismatch";

    return $self->{site_name};
}

=over B<$storage-E<gt>save(@objs)>

Save an object to the database (that is, do an insert if this is a new
object or an update if it is already persistent).

=cut

sub save($@) {
    my ($self, @objs) = (@_);
    $self->isa("T2::Storage") or die "type mismatch";

    my @return_vals;
    for my $obj (@objs) {
	if ($self->id($obj)) {
	    push @return_vals, $self->update($obj);
	} else {
	    push @return_vals, $self->insert($obj);
	}
    }

    return @return_vals;
}

sub ping {
    my $self = shift;
    eval {
	# *thwap* naughty!
	$self->{db}->do("select 1 + 1");
    };
    return !$@
}

=item unload_all()

A smarter version of unload_all() that really makes sure all objects
are cleaned up from memory, using Class::Tangram's clear_refs()
method.

=cut

sub unload_all {
    my $self = shift;

    my $objects = $self->{objects};
    if ($objects and ref $objects eq "HASH") {
	while (my $oid = each %$objects) {
	    if (defined $objects->{$oid}) {
		if (my $x = UNIVERSAL::can($objects->{$oid}, "clear_refs")) {
		    $x->($objects->{$oid});
		}
		$self->goodbye($objects->{$oid}, $oid);
	    }
	}
    }
    while (my $oid = each %$objects) {
	next unless defined $objects->{$oid};
	warn __PACKAGE__."::unload_all: cached ref to oid $oid "
	    ."is not weak"
		if (!$Tangram::no_weakrefs and
		    !Scalar::Util::isweak($objects->{$oid}));
	my $x;
	warn __PACKAGE__."::unload_all: refcnt of oid $oid is $x"
	    if (!$Tangram::no_weakrefs and
		$x = Set::Object::rc($objects->{$oid}));
    }
    $self->{ids} = {};
    $self->{objects} = {};
    $self->{prefetch} = {};
    print $Tangram::TRACE __PACKAGE__.": cache dumped\n"
	if $Tangram::TRACE;

    #$self->SUPER::unload_all();
}

=item rollback_all

Make double damned sure that this instance of the Storage handle
doesn't hold any locks

=cut

sub rollback_all {
    my $self = shift;
    while (@{ $self->{tx} }) {
	$self->tx_rollback
    }
    eval { $self->dbi_handle->rollback; };
    #local($self->{db}->{AutoCommit}) = 1;
}

=item dbi_handle()

Returns a current DBI handle, though you are not guaranteed to get
Tangram's own handle.

=cut

sub dbi_handle {
    my $self = shift;
    my $site_name = shift;
    $site_name ||= $self->{site_name};

    if ($self->{db} && $self->{db}->do("SELECT 1 + 1")) {
	return $self->{db};
    } else {
	my @dsn = $self->get_dsn_info($site_name, 1);
	return DBI->connect(@dsn);
    }
}

sub reopen_connection {
    my $self = shift;
    $self->{db} = $self->open_connection;

}

=back

=head1 AUTHOR

Sam Vilain, <samv@cpan.org>

=cut

1;
