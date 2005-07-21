
=head1 NAME

T2::Schema - Tangram Schemas, suitable for putting in a Tangram Store

=head1 SYNOPSIS

use T2::Schema;

my $schema = T2::Schema->load("site");
$schema->compile();

new Object();

=head1 DESCRIPTION


=cut

package T2::Schema;

use Storable qw(freeze thaw);
use Set::Object qw(blessed reftype);

use strict 'vars', 'subs';
use Carp;

use T2::Class;
use T2::Attribute;
use T2::Method;
use T2::Association;

use base qw(Class::Tangram);

# Ah, the T2::Schema Schema.  Presumably it's structure would be
# described as the T2::Schema Schema Schema.
our $schema =
    {
     fields =>
     {
      string => {
		site_name => { sql => "varchar(16) not null" },
		version => { sql => "VARCHAR(16)" },
		},
      idbif => {
		cid_size => undef,
		normalize => { sql => "TEXT" },
		table_type => { sql => "varchar(16)" },
		options => { init_default => {} },
	       },
      iarray => {
		 classes => {
			     aggreg => 1,
			     class => "T2::Class",
			     companion => "schema",
			     coll => "schema",
			    },
		},
      transient => {
		    schema => { class => "Tangram::Schema" },
		    schema_raw => { },
		    storage => { class => "Tangram::Storage" },
		    normalize_sub =>
		    {
		     init_default => sub {
			 sub {
			     local($_) = shift;
			     s/::/_/g;
			     s/^/_X_/ if m/^(grant|create|write|read|
					   group|when)$/ix;
			     return $_;
			 }
		     },
		    },
		    generator =>
		    { class => "Class::Tangram::Generator" },
		   },
     },
    };

Class::Tangram::import_schema(__PACKAGE__);

# the schema schema, this has to be a minor hack because of chicken
# and egg problems.
our $class_obj = __PACKAGE__->new
    (
     site_name => "schema",
     classes => [ map { T2::Class->new( name => "T2::$_" ) }
		  (qw(Class Attribute Association Method Schema)) ],
     normalize => '(my $name = shift) =~ s/T2:://; $name',
     options => { dumper => "YAML"
		},
    );

sub _obj {
    my $stackref = shift;
    if ( ref $stackref->[0] &&
	 UNIVERSAL::isa($stackref->[0], __PACKAGE__ ) ) {
	return shift @$stackref;
    } elsif ( UNIVERSAL::isa($stackref->[0], __PACKAGE__ ) ) {
	no strict "refs";
	my $class = shift @$stackref;
	return (${$class."::class_obj"} || $class_obj);
    } else {
	return $class_obj;
    }
}

=head1 METHODS

=over

=item B<T2::Schema-E<gt>load("site"[, $source])>

This is actually a constructor :-).

Load the schema for C<site> and return it.

C<$source>, if given, may be a Tangram::Storage object - in which case
it is assumed to be the schema database.  If missing,
T2::Storage->connect() is used to obtain a handle to the schema
database.

C<$source> may also be the correct Schema object, for convenience.  In
this case it is returned unchanged.

=cut

sub load {
    my $class = shift;
    my $site_name = shift;
    my $storage = shift;
    die unless ($site_name);
    unless (blessed($storage)) {
	eval "use T2::Storage";
	die $@ if $@;
	$storage = T2::Storage->open("schema", __PACKAGE__->schema);
    }

    my $source = $storage;

    if ($source->isa("Tangram::Storage")) {
	my $r_schema = $source->remote($class);
	($source) = $source->select
	    ($r_schema, $r_schema->{site_name} eq $site_name)
		or die("Could not load Schema object for `$site_name'"
		       ." from Schema database");
    } elsif ($source->isa(__PACKAGE__)) {
	die("Tried to load the schema for site `$site_name' from the "
	    ."schema for ".$source->site_name)
	    unless $source->site_name eq $site_name;
	$source = $storage;
    } else {
	die ("Trying to load a schema from a ".ref($source));
    }
    $source->set_storage($storage) if $storage;
    return $source;
}

=head2 B<$schema-E<gt>read_file("site" | $filename)>

This is actually a constructor :-).

Load a dumped schema for C<site> and returns it.  C<$filename>, if
given, may be the name of a file to use, or the site name (in which
case, the file name is assumed to be F<etc/site.t2>.

=cut

our @schema_path = qw(. etc ../etc);

sub read {
    my $class = shift;
    my $filename = shift;

    my $t2_file;
    for my $ext ("", ".t2") {
	for my $path (@schema_path) {
	    ( -f ($t2_file = "$path/${filename}$ext")) && last;
	    $t2_file = undef;
	}
    }
    die "Cannot find T2 schema for $filename in @schema_path"
	unless $t2_file;

    open DUMP, "<$t2_file"
	or die "Failed to open $t2_file for reading; $!";

    binmode DUMP;
    local($/)=undef;
    my $icicle = <DUMP>;
    close DUMP;

    my $self;
    eval {
	local($Storable::Eval) = 1;
	local($Storable::forgive_me) = 1;
	$self = thaw $icicle;
	$self->_fill_init_default();
	if ($self->{schema}) {
	    $self->{schema}->{normalize} = $self->{normalize_sub}
		unless ($self->{schema}->{normalize} and
			ref($self->{schema}->{normalize}) eq "CODE");
	    $self->{schema}->{make_object} = sub { shift()->new() }
		unless ($self->{schema}->{make_object} and
			ref($self->{schema}->{make_object}) eq "CODE");
	}
    };

    return $self;
}

=head2 $schema->compile

Loads all of the classes in the schema in to memory.

Tries to use on-disk versions rather than generating the in-memory
object & then compiling it.

The idea is that Class::Tangram version 2 uses `Class' objects as
input bread and butter rather than `schema' structures.  This should
eliminate the necessity for a huge `eval'.

This interface is deprecated in favour of using $schema->generator

=cut

sub compile {
    my $self = shift;

    # 1. compile/load the classes in superclass order
    for my $class ( sort {
	$a->superclass_size <=> $b->superclass_size
	    or $b->superclass_includes($a) <=> $a->superclass_includes($b)
	} $self->classes) {

	# skip if already loaded
	next if (Class::Tangram::attribute_types($class->name));

	my $found;
	if ($found = $class->on_disk) {
	    if ($class->is_uptodate($found)) {
		eval "require '$found';";
		if ($@) {
		    warn("Error loading `$found'; $@ - trying to compile");
		    $found = undef;
		}
	    } else {
		warn("File $found is older than the schema version; run "
		     ."sbin/update-classes.pl");
		$found = undef;
	    }
	}

	eval $class->as_module unless $found;

	if ($@) {
	    croak("Error while compiling class ".$class->name
		 ."; $@");
	} else {
	    # get Class::Tangram to import the class' schema
	    Class::Tangram::import_schema($class->name);
	}
    }
}

=head2 $schema->generator

Returns a Class::Tangram::Generator object that is valid for this
Schema.

=cut

sub get_generator {
    my $self = _obj(\@_);

    return $self->{generator} ||= do {

	my $module = 'Class::Tangram::Generator';
	eval 'use '.$module.' @_';
	die "Failed to load $module; $@" if $@;

	$module->new($self->schema_raw);
    }

}

=head2 $schema->schema_raw

Returns the data structure that is fed into Tangram::Schema->new().

Note that Tangram performs various in-place edits of this data
structure.  So don't go assuming too much about it.

=cut

sub get_schema_raw {
    my $self = _obj(\@_);

    return {(
      classes => [ map { $_->name => do { $_->schema_fragment } }
		   $self->classes                          ],
     )};
    
}


=head2 $schema->schema

=head2 $schema->schema_cooked

Generates a Tangram Schema for this Schema, or returns the one that
was already generated.  Use $schema->set_schema(undef) to force a
re-generation of the Tangram Schema structure.

=cut

# Alias the other methods
sub get_schema_cooked { my $self = _obj(\@_);
			return $self->get_schema(@_) };
sub set_schema_cooked { my $self = _obj(\@_);
			return $self->set_schema(@_) };
sub schema_cooked { my $self = _obj(\@_);
		    return $self->schema(@_) };

sub get_schema {
    my $self = _obj(\@_);

    if (!$self->{schema}) {
	my @classes;

	my %need;
	for my $class ($self->classes) {
	    next unless defined $class;
	    my $N = $class->name;

	    push @classes,
		$N => (${"${N}::schema"}
		       || ($a = ${"${N}::fields"}
			   ? { fields => $a }
			   : $class->schema_fragment ) );

	    $need{$_}++ foreach keys %{$classes[$#classes]->{fields}};
	}

	while (my $type = each %need) {
	    my $inc = $Class::Tangram::defaults{$type}->{load}
		or next;
	    do { $inc =~ s{(/)|(\.pm)}{$1 ? "::" : ""}eg;
		 eval "use $inc"; die $@ if $@; }
		unless exists $INC{$inc};
	}

	# ensure that holes in the classes list (ie, deleted classes)
	# are mapped correctly
	my $cid = 0;
	for my $class ($self->classes) {
	    $cid++;
	    next unless $class;
	    if (! $class->cid) {
		if (my $s = ${$class->name."::schema"}) {
		    $cid = $s->{id};
		}
		$class->set_cid($cid) unless $class->cid;
	    }
	}

    my %sql_o = %{ $self->options };

    $sql_o{table_type} = $self->table_type if $self->table_type;

        # FIXME - allow 
	$self->set_schema
	    ( new Tangram::Schema
	      ({
		cid_size => $self->cid_size,
	  	classes => \@classes,
		normalize => $self->normalize_sub,
		sql => \%sql_o,
	       })
	    );
    }

    return $self->{schema};
}

#sub schema {
    #my $invocant = shift;
    #return $invocant->get_schema(@_);
#}

=head2 $schema->storage

Returns the Tangram Storage class associated with this Schema.
Possibly connecting to the database.

=cut

sub get_storage {
    my $self = _obj(\@_);

    if (! $self->{storage} ) { #or !$self->{storage}->ping ) {
	croak ("no auto-storage from schema");
	$self->{storage}
	    = T2::Storage->connect($self->site_name,
				    $self->schema);
    }

    return $self->{storage};
}

=head2 $schema->class($name)

Returns the class definition for class C<$name>.

Croaks if there is no class C<$name>.

=cut

sub class {
    my $self = shift;
    my $name = shift or croak("no class name given to Schema->class");

    # Man, I gotta finish writin' me that Container::Object module
    my @results;

    if ($self->{class}) {
	my $class = $self->{class}->{$name}
	    or croak ("No such class `$name' in site `".$self->site_name
		      ."', just qw(".join(" ", map {$_?$_->name:"[undef]"}
					  $self->classes).")");

	return $class;

    } else {
	$self->{class} =
	    {
	     map { ($_ ? ($_->name => $_) : ()) } $self->classes
	    };
	return $self->class($name);
    }
}

sub set_classes {
    my $self = shift;
    delete $self->{class};
    return $self->SUPER::set_classes(@_);
}

=head2 $schema->class_exists($name)

Returns the class definition for class C<$name>.

Returns undef if no such class is found.

=cut

sub class_exists {
    my $self = shift;
    my $name = shift
	or croak("no class name given to Schema->class_exists");
    my $rv;
    eval { $rv = $self->class($name) };
    return $rv;
}

=head2 $schema->class_or_new($name)

Returns the class definition for class C<$name>.

Returns a new class if no such class is found.

=cut

sub class_or_new {
    my $self = shift;
    my $name = shift
	or croak("no class name given to Schema->class_or_new");

    my $rv;
    eval { $rv = $self->class($name) };

    if ($@) {
	return T2::Class->new(name => $name, schema => $self);
    } else {
	return $rv;
    }
}

=item add_class_from_schema($name => $schema)

Adds a Class object to this schema, gleaning information from
C<$schema>, which you perhaps found in $YourClass::schema.

=cut

sub add_class_from_schema {
    my $self = shift;
    my $name = shift;

    my $tangram_schema = shift;
    (reftype $tangram_schema eq "HASH")
	or croak("expecting ref HASH for `$name' class Schema, got "
		 ."`$tangram_schema'");

    my $class = $self->class_or_new($name);

    # Set various things from the schema
    $class->set_from_fields($tangram_schema->{fields} || {});
    $class->set_abstract($tangram_schema->{abstract} ? 1 : 0);
    $class->set_cid($tangram_schema->{id});
    $class->set_table($tangram_schema->{table});

    my @methods;
    while ( my ($name, $method)
	    = each %{$tangram_schema->{methods}||{}} ) {
	push @methods, T2::Method->new(name => $name,
				       code => $method);
    }
    $class->set_methods(@methods);

    # add to the schema - this will `knit' together the associations
    $self->classes_push($class);

    # setup the superclass
    if (my $bases = $tangram_schema->{bases}) {

	croak("Expecting array ref list of bases for class `$name', "
	      ."encountered `$bases'")
	    unless reftype $bases eq "ARRAY";

	my @superclasses = @$bases;

	croak("Sorry, T2 doesn't support MI in this release (class "
	      ."$name has superclasses @superclasses")
	    if (@superclasses > 1);

	if (my $sc_name = shift @superclasses) {
	    my $superclass = $self->class_or_new($sc_name);

	    $class->set_superclass($superclass);
	}
    }
}

=head2 $schema->sorted_classes

Returns the classes in inheritance first order.  Actually this
function is pretty redundant, you can just call C<sort
$schema-E<gt>classes>, but this implementation takes a different
approach.

=cut

sub sorted_classes {
    my $self = shift;

    my $seen = Set::Object->new();
    my $remaining = Set::Object->new($self->classes);

    my @order;
    while ($remaining->size()) {
	my @iter = grep { !$seen->includes($_) and
			      (!$_->superclass or
			       $seen->includes($_->superclass)) }
	    $remaining->members;
	$seen->insert(@iter);
	$remaining->remove(@iter);
	push @order, @iter;
    }

    return @order;
}

=head2 $schema->traverse(sub { })

Traverses over every object in the schema, setting $_[0] to the item.

=cut

sub traverse {
    my $self = shift;
    my $sub = shift;

    $_->traverse($sub) foreach grep { defined } $self->classes;
    $sub->($self) if $sub;
}

=head2 T2::Schema->self_schema()

Returns a structure of T2::Schema and related objects that represents
the schema of the T2::Schema modules.

=cut

sub self_schema {
    return $class_obj;
}

sub T2_import {
    my $self = shift;
    $self->set_normalize($self->normalize)
	if $self->normalize;
}

sub clear_refs {
    my $self = shift;
    delete $self->{normalize_sub};
    delete $self->{class};
    delete $self->{_class};
    $self->SUPER::clear_refs();
}

sub set_normalize {
    my $self = shift;
    my $s = $self->{normalize} = shift;
    $self->set_normalize_sub(eval("sub {".($s)."\n}"));
}

1;
