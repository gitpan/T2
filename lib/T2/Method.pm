#!/usr/bin/perl -w

package T2::Method;

use strict;

use base qw(Class::Tangram);

our $schema =
    {
     fields =>
     {
      string => {
		 name => { sql => "varchar(40)" },
		 code => { sql => "BLOB" },
		 js_code => { sql => "BLOB" },
		 # these are just comments for now
		 returnval => undef,
		 parameters => undef,
		 comment => {sql => "TEXT" },
		},
      ref => {
	      # back-reference
	      class => {
			class => "Class",
			companion => "methods",
		       },
	     },
      transient => {
		    is_accessor => undef,
		   },
      dmdatetime => {
		     # when this object last changed
		     changed => { sql => "TIMESTAMP" },
		    },
     }
    };


=head2 $method->traverse(sub { })

Traverses over every object in the method, setting $_[0] to the item.

=cut

sub traverse {
    my $self = shift;
    my $sub = shift;

    $self->class;
    $sub->($self) if $sub;

}

Class::Tangram::import_schema(__PACKAGE__);

1;
