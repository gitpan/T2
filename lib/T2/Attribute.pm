#!/usr/bin/perl -w

package T2::Attribute;
use strict;

=head1 NAME

T2::Attribute - an Attribute of a T2::Class

=head1 SYNOPSIS

  $class->attributes_insert
      ( T2::Attribute->new
           ( name => "myatt",
             type => "int",
             options => { sql => "TINYINT" }, ) );

=head1 DESCRIPTION

A T2::Attribute is an end-point in the T2 schema.  It is typically
mapped to a single column.

The following types are available:

=over

=item string

=item int

=item real

=item date

=item rawdatetime

=item rawdate

=item rawtime

=item flat_array

=item dmdatetime

=item flat_hash

=item perl_dump

=back

See L<Tangram::Type> for more information.

=cut

use base qw(Class::Tangram);

our $schema =
    {
     fields =>
     {
      string =>
      {
       type => {
		sql => ('enum('.join
			(",",map{qq{"$_"}}

			 qw(string int real ref array iarray set iset
			    date rawdatetime rawdate rawtime flat_array
			    dmdatetime hash flat_hash perl_dump)
			).')'),
		col => "_type",
		},
       # a description of the field
       name => undef,
       comment => { sql => "TEXT" },
      },
      ref => {
	      # the class we are a member of
	      class => {
			class => "T2::Class",
			companion => "attributes",
		       },
	     },
      int => {
	      # if set, never store this attribute in storage
	      transient => undef,

	      # if set, add an index on this column after DB creation
	      indexed => undef,
	     },
      perl_dump =>
      {
       # the hash passed to Tangram.  The more observant may notice
       # that this means you can't pass closures.  Oh well.  Perhaps
       # later.
       options => {
		   sql => 'text',
		   init_default => { },
		  },
      },
      dmdatetime => {
		     # when this object last changed
		     changed => { sql => "TIMESTAMP" },
		    },
     }
    };

sub example_value {
    my $self = shift;
    if ($self->get_type eq "string") {
	'"foo"';
    } elsif ($self->get_type eq "int") {
	'42';
    } elsif ($self->get_type eq "real") {
	'13.69';
    } elsif ($self->get_type eq "dmdatetime") {
	'&ParseDate("now")'
    } elsif ($self->get_type =~ m/flat_array/) {
	'[ (...) ]'
    } elsif ($self->get_type =~ m/flat_hash/) {
	'{ (...) }'
    } else {
	'(...)'
    }

}

# *cough cough hack hack*
sub is_enum {
    my $self = shift;

    return ($self->options->{sql} &&
	    $self->options->{sql} =~ m/^\s*enum\b/i);
}

sub enum_values {
    my $self = shift;

    # hooray, the day this horrible hack dies forever is within sight
    # :-)
    my $quoted_part = qr/(?: \"([^\"]+)\" | \'([^\']+)\' )/x;
    return grep { defined }
	($self->{options}->{sql} =~ m/$quoted_part/g);
}


# *cough cough hack hack*
sub is_set {
    my $self = shift;

    return ($self->options->{sql} &&
	    $self->options->{sql} =~ m/^\s*set\b/i);
}


sub required {
    my $self = shift;
    return ($self->{options}->{required});
}

sub max_length {
    my $self = shift;

    if ($self->{type} eq "string") {
	if (my $sql = $self->options->{sql}) {
	    if ($sql =~ m/^\s*(?:tiny|long|medium)?
			  (?:blob|text)/ix) {
		return ($1 ? ($1 eq "tiny"?255:2**24 - 1)
			: 2**16 - 1);
	    } elsif ($sql =~ m/^\s*(?:var)?char\s*\(\s*(\d+)\s*\)/ix) {
		return $1;
	    } else {
		return 255;
	    }
	} else {
	    return 255;
	}
    } elsif ($self->{type} eq "int") {
	if (my $sql = lc($self->options->{sql})) {
	    if ($sql =~ m/^\s*(tiny|small|medium|big)?int/) {
		return ($1 ? ($1 eq "tiny" ? 4 :  # -128 .. 127
			      ($1 eq "small" ? 6 : # -32768 .. 32767
			       ($1 eq "medium" ? 8 : # -8388608 .. 8388607
				20))) # -9223372036854775808 to (that*-1)-1
			: 10); # -2147483648 to 2147483647
	    }
	} else {
	    return 10;
	}
    } elsif ($self->{type} eq "real") {
	return 20;
    }
}

=head2 $assoc->traverse(sub { })

Traverses over every object in the attribute, setting $_[0] to the item.

=cut

sub traverse {
    my $self = shift;
    my $sub = shift;

    $self->class;
    $self->options;
    $sub->($self) if $sub;

}


Class::Tangram::import_schema(__PACKAGE__);

1;
