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

     int => {
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
	    },

     # auxilliary access to stick code in this class
     string => {
		init_code => {
			      sql => "BLOB"
			     },
		js_init_code => {
				 sql => "BLOB"
				},
		# documentation
		doc => {
			sql => "BLOB",
		       },
		name => {
			 sql => "VARCHAR(64)",
			},

		# SQL table name (optional)
		table => {
			  col => "_table",
			  },
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


=head2 as_prototype

Returns the Class as a JavaScript source file.

=cut

use Text::Wrap qw(wrap);

our %js_reserved_words =
    ( map { $_ => 1 }
      qw( abstract extends int super boolean false interface switch
	  break final long synchronized byte finally native this case
	  float new throw catch for null throws char function package
	  transient class goto private true const if protected try
	  continue implements public var default import return val do
	  name in short while double instanceof static with else)
    );

our %js_reserved_classes =
    (
     map { $_ => 1 }
     qw( Object Error Array Class
       )
    );
sub as_prototype {

    my $self = shift;
    my $anal_attributes_wanted = shift;

    if (!$INC{"JavaScript/Dumper.pm"}) {
	eval "use JavaScript::Dumper";
    }

    my $class_name = JavaScript::Dumper::classname($self->name);
    my $pkg_name = JavaScript::Dumper::pkgname($self->name);

    # hack hack hack
    $class_name =~ s{^}{_}
	if exists $js_reserved_classes{$class_name};

    # inheritance
    my ($proto_code, $init_code, $requires, $defered_code);
    $defered_code = "";
    my $constructor_code = <<"JS";
//--------------------------------------------------------------------
//  Prototype for `Class' $class_name
//--------------------------------------------------------------------
// Autogenerated by Class->as_prototype()
new Class("$class_name",function(a){
    if (a) {
        this.set(a);
    }
});
JS
    local($Text::Wrap::columns)=70;
    if ($self->doc) {
	$proto_code .= wrap(("// ")x2, $self->doc)."\n\n";
    }

    if ($self->js_init_code) {
	$proto_code .= $self->js_init_code."\n\n";
    }

    my ($parameters, $constructor_set) = ("", undef);
    if (my $constructor = $self->get_method("new")) {
      $parameters = $constructor->get_parameters;
      $constructor_code = <<"JS";
//--------------------------------------------------------------------
//  Prototype for `Class' $class_name
//--------------------------------------------------------------------
new Class("$class_name",function($parameters){
$constructor->js_code;
});
JS
      $constructor_set = 1;
    }

    my $post_string = "";

    # Deal with Superclasses
    if ($self->superclass and !$constructor_set) {
        my $superclass_name
	    = JavaScript::Dumper::classname($self->superclass->name);
	$requires
	    = JavaScript::Dumper::pkgname($self->superclass->name);
	$defered_code = <<"JS";
// Inherit all the properties of class $superclass_name
$class_name.inherits($superclass_name);

JS
    }

    # add the user or default constructor code
    $init_code .= $constructor_code."\n\n";

    $proto_code .= ("//".("-"x37)."\n"
		    ."//  Attributes\n\n");

    # Now, add all of the attributes, and accessor functions for them.
    for my $attribute ($self->get_attributes) {

	my $attribute_name = $attribute->name;
	my $lone_attribute_name = $attribute_name;

	if (exists $js_reserved_words{$attribute_name}) {
	    $lone_attribute_name =~ s/^/_/;
	}

	$proto_code .= wrap(("// ")x2, "$class_name.$attribute_name: "
			    .$attribute->type."; "
			    .($attribute->options->{sql}
			      ? " SQL: ".$attribute->options->{sql}
			      : " vanilla")."\n\n",
			    ($attribute->comment ? $attribute->comment : ())
			   )."\n\n";

	next if ($attribute->class != $self);

	unless ($self->cancan("get_$attribute_name")) {
	  $proto_code .= <<"JS";
$class_name.method("get_$attribute_name",function () {
    return this.$lone_attribute_name;
});

JS
	}
	
	unless ($self->cancan("set_$attribute_name")) {
	  $proto_code .= <<"JS";
$class_name.method("set_$attribute_name",function (value) {
    this.$lone_attribute_name = value;
});

JS
	}


      }
    $proto_code .= <<"JS";
$class_name.method("set",function(hashref) {
    var _self = this;
    var failed;
    hashref.map(function(value, field) {
        if (isFunction(x=_self['set_'+field])) {
            x.call(_self,value);
        } else {
            debug("Tried to set field "+field+" in a "+_self.Class);
            failed=1;
        }
    });
    failed && die("Bad arguments to set, dying");
});

$class_name.method("get",function(field) {
    if (isFunction(x=this['get_'+field])) {
	return x.call(this);
    } else {
        die("Tried to fetch field "+field+" from a "+this.Class);
    }
});

JS

    $proto_code .= ("//".("-"x37)."\n"
		    ."//  Associations\n\n");
    
    # same again, but for associations
    for my $association ($self->associations) {
	next if ($association->class != $self);

	my $association_name = $association->name;
	my $lone_association_name = $association_name;

	if (exists $js_reserved_words{$association_name}) {
	    $lone_association_name =~ s/^/_/;
	}


	#--------------------------------------------------
	# Multiple member associations
	if ($association->type =~ m/^(?:back-)?i?(set|array|hash)/) {

	  unless ($self->cancan("get_$association_name")) {
	    $proto_code .= <<"JS";
$class_name.method("get_$association_name", function(index) {
    if (index != NULL) {
        return this.${lone_association_name}\[index];
    } else {
        return this.${lone_association_name};
    }
});

JS
	  }
	  unless ($self->cancan("set_$association_name")) {
	    $proto_code .= <<"JS";
$class_name.method("set_$association_name", function(index, value) {
    if (isArray(index)) {
        this.$lone_association_name = index;
    } else if (isObject(index)) {
        this.$lone_association_name.push(index);
    } else if (!( index === null )) {
        this.${lone_association_name}\[index] = value;
    }
});

JS
	  }
	  #--------------------------------------------------
	  # Single member associations
	} elsif ($association->type =~ m/^(back-)?ref/) {

	  unless ($self->cancan("get_$association_name")) {
	    $proto_code .= <<"JS";
$class_name.method("get_$association_name", function() {
    return this.${lone_association_name};
});

JS
	  }
	  unless ($self->cancan("set_$association_name")) {
	    $proto_code .= <<"JS";
$class_name.method("set_$association_name", function(index, value) {
    if (isArray(index)) {
        this.$lone_association_name = index[0];
    } else if (isObject(index)) {
        this.$lone_association_name = index;
    } else {
        this.$lone_association_name = value;
    }
});

JS
	  }

	} else {
	    die("Unsupported association type");
	}

      }

    $proto_code .= ("//".("-"x37)."\n"
		    ."//  Methods\n\n");

    # Now all the methods
    for my $method ($self->methods) {
	next if ($method->class != $self);

	my $method_name = $method->name;
	my $lone_method_name = $method_name;

	if (exists $js_reserved_words{$method_name}) {
	    $lone_method_name =~ s/^/_/;
	}

	my $method_parameters = ($method->parameters)||"";
	my $code = $method->js_code || "";

	$proto_code .= <<"JS";
$class_name.method("$lone_method_name", function($method_parameters) {

$code

});

JS
    }

    s/\r\n/\n/g foreach ($proto_code, $init_code, $post_string);

    $class_name =~ s{^_}{};

    # Now put it all together and return it!
    return "//   -*- java -*-, or is that LISP?

Package('$pkg_name');

". ($requires ? "Include('$requires', function() { " : "")
."$init_code

$post_string
$defered_code;

$proto_code

\nPackage.ok('$pkg_name');".($requires?" });":"")."\n";

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

    $self->{attributes} ||= Set::Object->new();
    if (wantarray) {
	my @attribs;
	if ($self->superclass) {
	    push @attribs, $self->superclass->get_attributes;
	}
	push @attribs, sort { $a->name cmp $b->name }
	    $self->{attributes}->members;
	return @attribs;
    } else {
	return $self->{attributes};
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
		     name => $_,
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

	$self->reknit_associations();
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

=head2 as_module

Return this class as a string that may be written out to a .pm file

This method is 

=cut

sub as_module {
    my $self = shift;

    my %attrib;

    # this should be a TT template ;-)
    my $module_string = "#!/usr/bin/perl -w
package $self->{name};
use strict;

use base qw(". ($self->{superclass}
		? $self->{superclass}->name
		: "Class::Tangram")         .");
\n=head1 NAME

$self->{name} - the $self->{name} class (autogenerated by Class::as_module)
\n=head1 SYNOPSIS

".' my $foo = '.$self->{name}.'->new('. do{
    my $rc = "";
    for my $attrib ($self->attributes) {
	$attrib{$attrib->name} = $attrib;
	if ($attrib->required) {
	    $rc .= ($rc ? ",\n     " : "") .
		$attrib->name . " => " . ($attrib->example_value);
	}
    }
    $rc;
}.');
'.do{
     my @rc;
     for my $method ($self->all_methods) {
	 if ($method->is_accessor) {
	     $method->name =~ m/^(?:set_|get_)?(.*)/;
	     if (exists $attrib{$1}) {
		 if ($method->name =~ m/^set_(.*)/) {
		     push @rc, ' $foo->'.$method->name.'('
			 .($attrib{$1}->example_value).");\n";
		 } elsif ($method->name =~ m/^get/) {
		     push @rc, ' my $value = $foo->'.$method->name."();\n";
		 }
	     } else {
		 push @rc, ' my $value = $foo->'.$method->name."();\n";
	     }
	 } else {
	     push @rc, ' '.($method->returnval ? 'my $value = ' : '')
		 .'$foo->'.$method->name.'('
		 .($method->parameters||"").");\n";
	 }
    }
    join ("",@rc);
}."
\n=head1 DESCRIPTION

".($self->{doc}||"Sorry, no class documentation yet.")."\n\n";


    # build the Class::Tangram schema;
    my $seen_attr;
    for my $attribute ($self->attributes) {

	my $inherited = ($attribute->class != $self
			 ? $attribute->class->name : "");
	$module_string
	    .= ( ($seen_attr ? "" : do {
		    $seen_attr = 1;
		    "=head1 ATTRIBUTES\n\nThe following attributes "
			."have been defined for this class.\n\n";
		    })
		 . "=head2 ".$attribute->name ."\n\n"
		 .($inherited ? "This attribute is inherited "
		   ."from class $inherited\n\n" : "")
		 .($attribute->comment ? $attribute->comment."\n\n"
		   : "")
		 ."This attribute is of Tangram type (see "
		 ."L<Tangram::Type>) `"
		 .$attribute->type."'.\n\n");

	# Don't include inherited attributes
	next if $inherited;

    }

    unless ($seen_attr) {
	$module_string .= ("=head1 ATTRIBUTES (or, lack thereof)\n\n"
			   ."No attributes have been defined in this "
			   ."class, or are inherited from\nany "
			   ."superclasses.\n\n");
    }

    my $seen_assoc;
    for my $association ($self->associations) {

	my $inherited;
	$inherited = ($association->class != $self
		      ? $association->class->name : "");

	$module_string
	    .= ( ($seen_assoc ? "" : do {
		    $seen_assoc = 1;
		    "=head1 ASSOCIATIONS\n\nThe following "
			."associations have "
			."been defined for this class.\n\n"
		    })
		 . "=head2 ".$association->name_source."\n\n"
		 . ($inherited ? "This association is inherited from "
		    ."class $inherited.\n\n" : "")
		 . ($association->is_backwards ?
		    "This association is a back-reference "
		    ." from class ".$association->dest->name
		    .".\n\n" : "")
		 . ($association->comment
		    ? $association->comment."\n\n"
		    : "")
		 . "This is a ".$association->sm_text." to "
		 . $association->dm_text." relationship, that is "
		 . "implemented via Tangram type `".$association->rawtype
		 ."'.\n\n"
		 );

	# Don't include inherited associations
	next if $inherited;


    }

    unless ($seen_assoc) {
	$module_string .= ("=head1 ASSOCIATIONS (or, lack thereof)\n"
			   ."\nNo associations have been defined in "
			   ."this class, or are inherited from\nany "
			   ."superclasses.\n\n");
    }

    $Data::Dumper::Purity = 1;
    $Data::Dumper::Indent = 2;
    $Data::Dumper::Terse = 1;

    $module_string .=
	("=cut\n\nour \$schema = "
	 .Dumper($self->schema_fragment)
	 . ";\n\nClass::Tangram::import_schema('$self->{name}');\n\n"
	 . ($self->init_code ? $self->init_code."\n\n" : "")
	);

    my $any_methods_defined;
    for my $method ($self->methods) {

	my $inherited = ($method->class != $self
			 ? $method->class->name : "");

	unless ($any_methods_defined) {
	    $any_methods_defined = 1;
	    $module_string .= ("=head1 METHODS\n\nThe following "
			       ."methods are defined for this Class."
			       ."\n\n");

	}
	$module_string .= "=head2 ".$method->name.
	    ($method->parameters ? "(".$method->parameters.")" : "");
	$module_string .= ($method->returnval
			   ? " : ".$method->returnval
			   : "");
	$module_string .= ("\n\n".
			   ($inherited ? "This method is inherited "
			    ."from class $inherited" : "").
			   ($method->comment
			    ||"No comment defined!  UTSL")
			   ."\n\n=cut\n\n");

	# Don't include inherited methods
	next if $inherited;

	$module_string .= "sub ".$method->name." {\n";
	$module_string .= $method->code."}\n\n";
    }
    unless ($any_methods_defined) {
	$module_string .= ("=head1 METHODS (or, lack thereof)\n"
			   ."\nNo associations have been defined in "
			   ."this class, or are inherited from\nany "
			   ."superclasses.\n\n=cut\n\n");
    }

    $module_string .= "42;\n";

    $module_string =~ s/\r\n/\n/g;

    return $module_string;
}

Class::Tangram::import_schema(__PACKAGE__);

1;

=back

=cut

