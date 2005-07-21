#!/usr/bin/perl -w

=head1 NAME

T2::Class - Classes in a T2 schema

=head1 SYNOPSIS

  my $class = T2::Class->new
      ( name => "My::Package",
        table => "db_table",    # optional
        attributes => [ ... ],
        associations => [ ... ],
        methods => [ ... ] );

=head1 DESCRIPTION

A T2::Class is a class in a Tangram schema.

=cut

# Handy for emacs:
# (mmm-ify-by-regexp 'java-mode "<[<]\"JS\"" 2 "^JS$" 0 1)

package T2::Class;

use strict 'vars', 'subs';
use Carp;

use Data::Dumper;
use Date::Manip qw(ParseDateString);
use Set::Object qw(refaddr reftype);

use base qw(Class::Tangram);
use overload
    '<=>' => \&compare,
    '==' => \&equal,
    fallback => 1;

our $schema =
    {
     fields =>
     {
     # the standard stuff
     iset => {
	      attributes => {
			     class => "T2::Attribute",
			     companion => "class",
			     coll => "class",
			     aggreg => 1,
			    },
	      associations => {
			       class => "T2::Association",
			       companion => "class",
			       coll => "class",
			       aggreg => 1,
			      },
	      methods => {
			  class => "T2::Method",
			  companion => "class",
			  coll => "class",
			  aggreg => 1,
			 },

	      rev_assocs => {
			     class => "T2::Association",
			     companion => "dest",
			     coll => "dest",
			    },
	      subclasses => {
			     class => "T2::Class",
			     companion => "superclass",
			     coll => "superclass",
			    },
	      },
     # no multiple inheritance allowed at this level!
     ref => {
	     superclass => {
			    class => "T2::Class",
			    companion => "subclasses",
			   },
	     'schema' => {
			  'class' => 'T2::Schema',
			  'companion' => 'classes',
			 },
	    },

     idbif => {
	       # is this an abstract class?
	       abstract => undef,

	       # is this class a candidate for having its module file
	       # re-written?
	       auto => { sql => "TINYINT",
			 init_default => 1 },

	       # is this class a candidate for having its prototype file
	       # re-written?
	       js_auto => { sql => "TINYINT",
			    init_default => 1 },

	       # is this class able to be modified?
	       frozen => { sql => "TINYINT",
			   init_default => 0 },

	       # The Class ID of this class (optional)
	       cid => { sql => "INT(6)" },

	       init_code => {
			    },
	       js_init_code => {
			       },
	       # documentation
	       doc => {
		      },

	       # SQL table name (optional)
	       table => {
			},
	      },
      string => {
		 name => undef,
		},

      dmdatetime => {
		     # when this object last changed
		     changed => { sql => "TIMESTAMP" },
		    },
     }
    };

=head2 schema_fragment

Returns the Tangram::Schema fragment that corresponds to this class.

=cut

sub schema_fragment {
    my $self = shift;

    my $schema_fields;

    for my $attribute ($self->attributes) {
        next unless $attribute->class == $self;

	my $fields_list = $schema_fields->{$attribute->type} ||= { };
	$fields_list->{$attribute->name}
	    = { #doc => $attribute->comment,
		%{ $attribute->options||{} } };
    }

    for my $association ($self->associations) {
        next unless $association->class == $self;

	my $fields_list = $schema_fields->{$association->rawtype} ||= { };

	$fields_list->{$association->name_source}
	    = { #doc => $association->comment,
	        ( $association->name_dest
		  ? (companion => $association->name_dest)
		  : () ),
		%{ $association->options||{} },
	       ($association->dest ? (class => $association->dest->name) : ()),
	       ($association->composite ? (aggreg => 1) : ()),
	      };
    }

    my $schema_methods;

    for my $method ($self->methods) {
	$schema_methods ||= {};
        next unless $method->class == $self;

	my $closure;
	eval '$closure = sub {'.$method->code."\n}";

	warn "Sub ".$self->name."::".$method->name." failed to "
	    ."compile; $@" if $@;

	$schema_methods->{ $method->name } = $closure
	    if $closure and not $@;
    }

    return({
	    fields => ( $schema_fields || {} ),
	    ( $self->superclass ?
	      ( bases => [$self->superclass->name]) : () ),
	    ( $self->table ?
	      ( table => $self->table) : () ),
	    ( $self->cid ?
	      ( id => $self->cid ) : () ),
	    
	   });

}

=item $class->attributes

In list context, returns all of the attributes (NOT associations) that
this class has, I<including attributes defined in parent classes>.
The ordering of the returned attributes is stable.

In scalar context, return a Set::Object which is the list of
attributes that belong to I<this class only>.

=cut

# Returns all attributes of this class, inherited and otherwise
sub get_attributes {
    my $self = shift;

    if (wantarray) {
	my @attribs;
	if ($self->superclass) {
	    push @attribs, $self->superclass->get_attributes;
	}
	push @attribs, sort { $a->name cmp $b->name }
	    $self->SUPER::get_attributes->members;
	return @attribs;
    } else {
	return $self->SUPER::get_attributes;
    }
}

=item $class->associations

In list context, returns all of the associations this class has,
I<including associations defined in parent classes>.  The ordering of
the returned associations is stable.

It will also include associations that are I<not> from this class but
B<to> this class, but only if the association has a name defined for
the back-reference.  The association is in this case a mirror of the
association for the original reference.  Such associations are
detectable, because they return 1 to $association->is_backwards();

In scalar context, return a Set::Object which is the list of
associations that belong to I<this class only>, and without the
backwards associations.

=cut


# Returns all attributes of this class, inherited and otherwise
sub get_associations {
    my $self = shift;

    if (wantarray) {

	my @associations;
	if ($self->superclass) {
	    push @associations, $self->superclass->get_associations;
	}

	push @associations,
	    sort { $a->name cmp $b->name }
		grep { $_->name }
		    $self->SUPER::get_associations->members;

	push @associations,
	    sort { $a->name cmp $b->name }
		map { $_->inverse }
		    grep { $_->name_dest }
			$self->rev_assocs->members;

	return @associations;

    } else {
	return $self->SUPER::get_associations(@_);
    }
}

=item $class->rev_assocs

In list context, returns all of the associations that I<refer> to this
class, I<including associations defined in parent classes>.

It will also include associations that are I<not> B<to> this class but
B<from> this class, but only if they have both names (source and
destination) defined.  The association is in this case a mirror of the
association for the original reference.  Such associations are
detectable, because they return 1 to $association->is_backwards();

In scalar context, return an ARRAY ref which is the list of
associations that belong to I<this class only>, and without the
backwards associations.

=cut


sub get_rev_assocs {
    my $self = shift;

    if (wantarray) {
	my @rev_assoc;

	if ($self->superclass) {
	    push @rev_assoc, $self->superclass->get_rev_assocs;
	}

	push @rev_assoc,
	    sort { $a->name_dest cmp $b->name_dest }
		$self->SUPER::get_rev_assocs->members;

	push @rev_assoc,
	    sort { $a->name_dest cmp $b->name_dest }
		map { $_->inverse }
		    grep { $_->name_dest }
			$self->associations->members;

	return @rev_assoc;

    } else {
	return $self->SUPER::get_rev_assocs(@_);
    }
}

=item $class->methods

In list context, this method returns all of the methods that this
class has defined as T2::Method objects, I<including inherited
methods>.  In some cases this may mean you get a method twice, if it
is over-ridden by a sub-class.

In scalar context, returns a Set::Object with all of the methods in
it, for I<only this class>.

=cut

sub get_methods {
    my $self = shift;

    if (wantarray) {
	my @methods;
	if ($self->superclass) {
	    push @methods, $self->superclass->get_methods;
	}
	push @methods,
	    sort { $a->name cmp $b->name } $self->SUPER::get_methods;
	return @methods;
    } else {
	return $self->SUPER::get_methods(@_);
    }


}

=item $class->all_methods

The all_methods function augments the list returned by the C<methods>
function by including accessor methods that the attributes and
associations defined by the class would include.

This assumes that you are generating your classes using the included
class generator, and using them with Class::Tangram 1.50+.

=cut

sub all_methods {
    my $self = shift;

    if (wantarray) {
	my @methods = $self->methods;

	my %meths = map { $_->{name} => 1 } @methods;

	for my $attribute ($self->attributes) {
	    for my $type ("", qw(get_ set_)) {
		if (!exists($meths{my $name = $type.$attribute->name})) {
		    my $m;
		    push @methods,
			$m = T2::Method->new(
					     name => $name,
					     is_accessor => 1
					    );
		    $m->{class} = $self;
		}
	    }
	}

	for my $assoc ($self->associations) {
	    # missing : exists, storesize, firstkey, nextkey, 
	    for my $type ("", qw(get_ set_ _includes _insert _replace
				 _push _pop _shift _unshift _splice
				 _pairs _size _clear _remove)) {
		my $name;
		if ($type =~ m/^_/) {
		    $name = $assoc->name.$type;
		} else {
		    $name = $type.$assoc->name;
		}
		if (!exists($meths{$name})) {
		    my $m;
		    push @methods,
			$m = T2::Method->new(
					 name => $name,
					 is_accessor => 1
					);
		    $m->{class} = $self;
		}
	    }
	}

	return @methods;
    } else {
	return Set::Object->new($self->methods, $self->all_methods);
    }

}

=item $class->get_method("name")

Returns the method named by "name" for this class.

If defined in more than one superclass, returns the most specific
version.

=cut

sub get_method {
    my $self = shift;
    my $name = shift;

    my (@methods) =  grep { $_->name eq $name } $self->get_methods;
    return pop @methods;
}

=item $class->method(...)

If given a T2::Method object, then it adds that method to this Class'
list.

If given the name of a method, returns the method that matches that
name.

=cut

sub method {
    my $self = shift;
    my $name = shift;

    if (UNIVERSAL::isa($name, "Method")) {
	$self->methods_insert($name);
    } elsif (my $sub = shift) {
	die "Not implemented yet";
    } else {
	return $self->get_method($name);
    }

}

=item $class->get_attribute($name)

=item $class->attribute(...)

get_attribute(), or attribute() with only the name of an attribute
return the T2::Attribute object that is the attribute.

attribute() can also be used to add attributes to the class, if passed
an Attribute object.

=cut

sub get_attribute {
    my $self = shift;
    my $name = shift;

    my ($att) = grep { $_->name eq $name } $self->get_attributes;
    return $att;
}

sub attribute {
    my $self = shift;
    my $name = shift;
    if (UNIVERSAL::isa($name, "Attribute")) {
	$self->attributes_insert($name);
    } else {
	return $self->get_attribute($name);
    }
}

=item $class->get_association($name)

=item $class->association(...)

get_association(), or association() with only the name of an
association return the T2::Association object that is the association.

association() can also be used to add associations to the class, if
passed an Association object.

=cut

sub get_association {
    my $self = shift;
    my $name = shift;

    my ($ass) = grep { $_->name eq $name } $self->get_associations;
    return $ass;
}

sub association {
    my $self = shift;
    my $name = shift;
    if (UNIVERSAL::isa($name, "Association")) {
	$self->associations_insert($name);
    } else {
	return $self->get_association($name);
    }
}

=item $class->cancan("method")

Returns the T2::Method object that implements the passed method, or
undef.

This will never return an accessor, unlike
C<$class-E<gt>get_method("method")>.

=cut

sub cancan {
    my $self = shift;
    my $method = shift or croak "usage: Class->cancan('method')";

    if (my @x = grep { $_->name eq $method }
	$self->{methods}->members) {
	return shift @x;
    }

    if ($self->superclass) {
	return $self->superclass->cancan($method);
    }

    return undef;
}

=item $class->on_disk()

Returns the path to the .pm that corresponds to this path, if found in
@INC.

=cut

sub on_disk {
    my $self = shift;

    (my $fn = $self->name) =~ s{::}{/}g;
    my $found;
    for my $path (@INC) {
	my $a = "$path/$fn.pm";
	if ( -f $a ) {
	    $found = $a;
	    last;
	}
    }
    return $found;
}

=item $class->is_uptodate([ $filename ])

Returns true if the version of the class on the disk is newer than the
newest of the class, and all of its attributes, associations and
methods.

=cut

sub is_uptodate {
    my $self = shift;
    my $found = (shift) || $self->on_disk;

    if ($found and (stat $found) and
	(my $time = &ParseDateString("epoch ". ((stat _)[9])))
       ) {

	if (grep { $time lt $_->changed }
	    ($self, $self->attributes,
	     $self->associations, $self->methods)) {
	    return undef;
	} else {
	    return $found;
	}
    } else {
	return undef;
    }
}

=item $class->is_a($what)

Identical to the Perl UNIVERSAL::isa method, but works on the Schema
structure rather than the compiled @SomeClass::ISA variables.

=cut

sub is_a {
    my $self = shift;
    my $what = shift;
    if (ref $what) {
	if ($self == $what
	    or $self->superclass && $self->superclass->is_a($what)) {
	    return 1;
	} else {
	    return undef;
	}
    } else {
	return $self->SUPER::isa($what, @_);
    }
}

=item $class->compare($class2)

Returns 0 if the classes are the same, or are unrelated.

Returns 1 if $class2 is a I<descendant> of $class

Returns 2 if $class2 is a I<superclass> of $class

What this means is if you use code like this:

    my @classes = sort $schema->classes;
    eval ("use $_;") foreach @classes;

You're guaranteed not to have any inheritance dependancy problems.

=cut

sub compare {
    my $self = shift;
    my $other = shift;
    carp("Apples, oranges: ".ref($self)." vs ".ref($other)||$other),
	return undef
	    unless UNIVERSAL::isa($other, __PACKAGE__);

    if ($self == $other) {
	return 0;
    }
    if ($self->is_a($other)) {
	return 1;
    }
    if ($other->is_a($self)) {
	return -1;
    }
    return 0;
}

sub equal {
    # hmm, pretty general purpose :-)
    my $a = shift;
    my $b = shift;
    return (refaddr($a) == refaddr($b));
}

=item set_from_fields($fields)

Sets up fields in a T2::Class object, gleaning information from
C<$fields>, which you perhaps found in $YourClass::fields, or perhaps
a section of an existing Tangram 2 schema.

Note that it is not possible to set up association objects correctly
until all associations are present in the schema.  This will
automatically happen when you insert Classes into the schema.

=cut

sub set_from_fields {
    my $self = shift;
    my $fields = shift || {};

    # extract all the fields
    croak("expecting ref HASH for fields list, got "
	  ."`$fields'") unless (reftype $fields eq "HASH");

    my (@attributes, @associations);

    while (my ($type, $fieldlist) = each %$fields) {
	next if $type eq "backref";

	$fieldlist = { map { $_ => undef } @$fieldlist }
	    if ref $fieldlist eq "ARRAY";

	croak("Expecting ref HASH for field list for type `$type', "
	      ."got `$fields'") unless reftype $fieldlist eq "HASH";

	if ($type =~ m/^((i)?(set|hash|array)|ref)$/) {
	    while (my ($field, $options) = each %$fieldlist) {
		# associations...
		$options ||= {};
		$options = { %$options };
		my $x;
		push @associations, T2::Association->new
		    (
		     name_source => $field,
		     order => ($3||"set"),
		     source_min => 0,
		     source_max => ($2 ? 1 : -1),
		     dest_min => 0,
		     dest_max => ( ($2||$3) ? -1 : 1 ),
		     ( delete $options->{aggreg} ?
		       ( composite => 1 ) : () ),
		     #( $x = delete $options->{class} ?
		       #( dest => $T2::Class->new(name => $x) ) : () ),
		     ( ($x = delete $options->{back}) ?
		       ( name_dest => $x ) : () ),
		     options => $options,
		    );
	    }
	} elsif ($type eq "transient") {
	    while (my ($field, $options) = each %$fieldlist) {
		# transient attribute...
		$options ||= {};
		$options = { %$options };

		push @attributes, T2::Attribute->new
		    (
		     name => $field,
		     type => (delete $options->{type}||"perl_dump"),
		     transient => 1,
		     options => $options,
		    );
	    }
	} else {
	    while (my ($field, $options) = each %$fieldlist) {
		# attribute...
		$options ||= {};
		$options = { %$options };

		push @attributes, T2::Attribute->new
		    (
		     name => $field,
		     type => $type,
		     options => $options,
		    );
	    }
	}
    }

    #kill 2, $$ if $self->name =~ /CGI/;
    $self->attributes_insert(@attributes);
    $self->associations_insert(@associations);

    return $self;

}

sub set_schema {
    my $self = shift;
    my $new_schema = shift;
    my $old_schema = $self->{schema};

    if (refaddr($old_schema) != refaddr($new_schema)) {
	$self->{schema} = $new_schema;

	# ok, the schema has changed, check all our superclasses,
	# attributes, etc for a different schema
	$self->superclass->set_schema($new_schema)
	    if $self->superclass;

	$self->reknit_associations()
	    if $new_schema;
    }
}

sub reknit_associations {
    my $self = shift;

    for my $association ($self->associations->members) {

	if (!$association->dest or
	    refaddr($association->dest->schema) !=
	    refaddr($self->schema)) {

	    my $dest_name = ($association->options->{class} ||
			     ($association->dest
			      ? $association->dest->name
			      : die("no class option for "
				    .$association->name)));

	    my $dest_class = $self->schema->class($dest_name);

	    $association->set_dest($dest_class);

	    $association->options->{class} = $dest_name
		if not $dest_class;
	}
    }
}

=head2 $class->traverse(sub { })

Traverses over every object in the class, setting $_[0] to the item.

=cut

sub traverse {
    my $self = shift;
    my $sub = shift;

    $_->traverse($sub) foreach $self->associations->members;
    $_->traverse($sub) foreach $self->attributes->members;
    $_->traverse($sub) foreach $self->methods->members;

    scalar($self->schema);
    scalar($self->rev_assocs);
    scalar($self->subclasses);
    scalar($self->superclass);
    $sub->($self) if $sub;

}

Class::Tangram::import_schema(__PACKAGE__);

1;

=back

=cut

