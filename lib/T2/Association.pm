#!/usr/bin/perl

package T2::Association;
use strict;
no warnings;

=head1 NAME

T2::Association - an association in a T2 Schema

=head1 SYNOPSIS

  t.b.c.

=head1 DESCRIPTION



=cut

use base qw(Class::Tangram);
use Carp qw(croak cluck);

our $schema =
    {
     fields =>
     {
      ref => {
	      # The target class of the association (referant)
	      dest => {
		       class => "Class",
		       companion => "rev_assocs",
		      },
	      # The source class of the association (referer)
	      class => {
			class => "Class",
			companion => "associations",
		       },
	     },

      idbif =>
      {
       # what the attribute in the target/source class is called
       name_source => undef,
       name_dest => undef,

       # a description of the association
       comment => { sql => "TEXT" },

       # Is this an unordered, ordered or keyed relationship?
       order => { sql => 'enum("set", "array", "hash")',
		  col => '_order'
		},
       # if set, never store this association in storage
       #
       # Note: this currently isn't a good idea for anything
       # except *->1 associations (references)
       transient => undef,

       # multiplicity of the association (-1 is considered
       # `infinity')
       source_min => { init_default => 1 },
       source_max => { init_default => 1 },

       dest_min   => { init_default => 1 },
       dest_max   => { init_default => 1 },

       # This indicates a composite (as opposed to aggregate)
       # relationship
       composite  => { sql => "TINYINT" },
       options => {
		   sql => 'blob',
		  },
      },

      transient => {
		   # set if this is a result from Association.inverse
		   is_backwards => undef,
		   },


      dmdatetime => {
		     # when this object last changed
		     changed => { sql => "TIMESTAMP" },
		    },
     },
    };


sub indexed { return undef}

sub name { return (shift)->get_name_source(@_); }
sub get_name { return (shift)->get_name_source }
sub set_name { return (shift)->set_name_source(@_); }

# Returns the Tangram association type required for this type of
# association
sub type {
    my $self = shift;

    return(($self->is_backwards ? "back-" : "").$self->rawtype);

    
}

sub rawtype {
    my $self = shift;

    if ($self->get_dest_max == 1) {
	# a 1 -> 1 reference
	return "ref";
    }

    if ($self->get_source_max == 1) {
	# it is an Intr type
	return "i".$self->order;
    } else {
	# it is not an intr type
	return $self->order;
    }
}

no strict "subs";

sub get_source_max {
    my $self = shift;

    if ($self->{source_max} == -1) {
	# FIXME - perl handling of `inf' is inconsistent
	return +99999;
    } else {
	return $self->{source_max};
    }
}

sub get_dest_max {
    my $self = shift;

    if ($self->{dest_max} == -1) {
	return +99999;
    } else {
	return $self->{dest_max};
    }
}

sub set_source_max {
    my $self = shift;
    my $new_val = shift;
    local ($^W) = 0;
    warn("Cannot set maximum source multiplicity to 0; ".$self->quickdump)
	if ($new_val == 0);
    if ($new_val eq "*" or $new_val == 99999) {
	$self->{source_max} = -1;
    } else {
	$self->{source_max} = $new_val;
    }
}

sub set_dest_max {
    my $self = shift;
    my $new_val = shift;
    local ($^W) = 0;
    warn("Cannot set maximum destination multiplicity to 0; ".$self->quickdump)
	if ($new_val == 0);

    if ($new_val eq "*" or $new_val == 99999) {
	$self->{dest_max} = -1;
    } else {
	$self->{dest_max} = $new_val;
    }
}

#---------------------------------------------------------------------
#  sm_text() : returns the multiplicity of a link in textual form, eg
# "1..*", "1", "3..*", etc
#---------------------------------------------------------------------
sub sm_text {
    my $self = shift;
    return multiplicity($self->get_source_min, $self->get_source_max);
}
sub dm_text {
    my $self = shift;
    return multiplicity($self->get_dest_min, $self->get_dest_max);
}
sub multiplicity {
    my $min = int(shift);
    my $max = int(shift);

    if ($min == $max) {
	return "$min";
    } else {
	if ($max == 99999) {
	    $max = "*";
	    if ($min == 0) {
		return $max;
	    }
	};
	return "$min .. $max";
    }
}

sub source_max_text {
    my $self = shift;
    if ((my $max = $self->get_source_max) == 99999) {
	return "*";
    } else {
	return $max;
    }
}

sub dest_max_text {
    my $self = shift;
    if ((my $max = $self->get_dest_max) == 99999) {
	return "*";
    } else {
	return $max;
    }
}

sub inverse {
    my $self = shift;

    my $inverse = __PACKAGE__->new
	(
	 name_source => $self->name_dest,
	 name_dest   => $self->name_source,

	 comment    => $self->comment,

	 # inverse relationships are always sets
	 order      => "set",

	 transient  => $self->transient,

	 source_min => $self->dest_min,
	 source_max => $self->dest_max,

	 dest_min   => $self->source_min,
	 dest_max   => $self->source_max,

	 composite  => 0,

	 changed    => $self->changed,

	 is_backwards => 1
	);

    $inverse->{dest} = $self->class;
    $inverse->{class} = $self->dest;

    return $inverse;
}


=head2 $attrib->traverse(sub { })

Traverses over every object in the associaiton, setting $_[0] to the item.

=cut

sub traverse {
    my $self = shift;
    my $sub = shift;

    $self->dest;
    $self->class;
    $self->options;
    $sub->($self) if $sub;

}

Class::Tangram::import_schema(__PACKAGE__);

1;
