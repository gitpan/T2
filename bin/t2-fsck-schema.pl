#!/usr/bin/perl -w

use strict;
use lib "var/lib/perl";
use lib "lib";
use T2::Schema;
use T2::Storage;
use DBI;

my $site = (shift) || "schema";

my $schema_storage = T2::Storage->open("schema");

my $schema = ($site eq "schema" ? $T2::Schema::class_obj : 
	      do {
		  my $r_schema = $schema_storage->remote("T2::Schema");
		  my @res = $schema_storage->select
		      ($r_schema,
		       $r_schema->{site_name} eq $site);
		  $res[0]
		  });

my $generator = $schema->generator() unless $site eq "schema";

my @dsn = T2::Storage::get_dsn_info($site)
  or die "Failed to get DSN info for site $site";

my $dbh = DBI->connect(@dsn) or die $DBI::errstr;

# Look for all associations with companions & check that they match up
no strict "refs";

use Data::Dumper;

my @classes = ($site eq "schema" ? Class::Tangram::companions()
	       : map { $_->name } grep { defined $_ } $schema->classes );
for my $class (@classes) {
    print "[ $class ]\n";
    $generator->load_class($class) if $generator;
  my $companions = Class::Tangram::companions($class);
  my $options = Class::Tangram::attribute_options($class);
  my $types = Class::Tangram::attribute_types($class);

  while (my ($attribute, $companion) = each %$companions) {

    my $dest = $options->{$attribute}->{class} || die "No dest to $class.$attribute!";
    $generator->load_class($dest) if $generator;
    if (!Class::Tangram::attribute_types($dest)) {
	die "No Class::Tangram prototype loaded for $dest";
    }
    my $other_type = Class::Tangram::attribute_types($dest)->{$companion}
	or die ("$dest -> $companion is not defined!");

    print "Class $class attribute $attribute (type $types->{$attribute}) is companion to $dest attribute $companion (type $other_type)\n";

    # find the mapping in the Tangram schema object
    my ($from_tt, $to_tt);
    my @bases;
    sub sch_cls {
	my $class = shift;
	print "Asked for schema class for $class\n";
	return $schema->schema->{classes}->{$class};
    }
    my $super;
    my $set = Set::Object->new(sch_cls(@bases = $class)||die);
    while ($super = shift @bases) {
	if ($from_tt = $schema->schema->{classes}
	    ->{$super}->{fields}->{$types->{$attribute}}->{$attribute}) {
	    last;
	}
	push @bases,
	    grep { $set->insert(sch_cls($_)) }
	    @{ $schema->schema->{classes}->{$super}->{bases} };
	$super = undef;
    }
    if (!defined ($super)) {
	print "Very bizarre error in $class!\n";
    } elsif ( $super ne $class) {
	print "Skipping $class"."->$attribute; inherited\n";
	next;
    }

    $set = Set::Object->new(sch_cls(@bases = $dest));
    while ($super = shift @bases) {
	if ($to_tt = $schema->schema->{classes}
	    ->{$super}->{fields}->{$other_type}->{$companion}) {
	    last;
	}
	push @bases,
	    grep { $set->insert(sch_cls($_)); }
	    @{ $schema->schema->{classes}->{$super}->{bases} };
	$super = undef;
    }

    if (!defined ($super)) {
	print "Invalid companion - ${class}->$attribute tried to join with ${dest}->{$companion}, which doesn't exist!\n";
	next;
    } elsif ( $super ne $class) {
	# not an error
    }

    if ($types->{$attribute} =~ m/^i?(set|array|hash)/) {
      my $indexing = $1;
      if ($other_type =~ m/^i?(set|array|hash)/) {
	  # many to many
	  if ($from_tt->{coll} ne $to_tt->{item}) {
	      print "Warning: From coll ( $from_tt->{coll} ) ne Back item ( $to_tt->{item} )\n";
	      my $att = $schema->class($dest)->association($companion);
	      if ($schema_storage->id($att)) {
		  print "Fix ( set Back item to $from_tt->{coll} ) ? ";
		  if (askyn()) {
		      if (!$att->options) {
			  $att->set_options({});
		      }
		      $att->options->{"item"} = $from_tt->{coll};
		      local($Tangram::TRACE) = \*STDOUT;
		      $schema_storage->update($att);
		  }
	      } else {
		  print "Can't fix, skipping\n";
	      }
	  }
	  if ($from_tt->{item} ne $to_tt->{coll}) {
	      print "Warning: From item ( $from_tt->{item} ) ne Back coll ( $to_tt->{coll} )\n";
	      my $att = $schema->class($dest)->association($companion);
	      if ($schema_storage->id($att)) {
		  print "Fix ( set Back item to $from_tt->{item} ) ? ";
		  if (askyn()) {
		      if (!$att->options) {
			  $att->set_options({});
		      }
		      $att->options->{"coll"} = $from_tt->{item};
		      local($Tangram::TRACE) = \*STDOUT;
		      $schema_storage->update($att);
		  }
	      } else {
		  print "Can't fix, skipping\n";
	      }
	  }
      } elsif ($other_type eq "ref") {
	# a one to many mapping - check for objects with broken back-refs
	  if ($from_tt->{coll} ne $to_tt->{col}) {
	      print "Warning: From coll ( $from_tt->{coll} ) ne To col ( $to_tt->{col} )\n";
	      my $att = $schema->class($dest)->association($companion);
	      if ($schema_storage->id($att)) {
		  print "Fix ( set To col to $from_tt->{coll} ) ? ";
		  if (askyn()) {
		      if (!$att->options) {
			  $att->set_options({});
		      }
		      $att->options->{"col"} = $from_tt->{coll};
		      local($Tangram::TRACE) = \*STDOUT;
		      $schema_storage->update($att);
		  }
	      } else {
		  print "Can't fix, skipping\n";
	      }
	  }
      } else {
	print STDERR "Wierd schema!  $types->{$attribute} to $other_type!\n";
      }
    }

    if ($types->{$attribute} eq "ref") {
      if ($other_type =~ m/^i?(set|array|hash)/) {
	# a one to many mapping - this will be found in both directions
	  if ($from_tt->{col} ne $to_tt->{coll}) {
	      print "Warning: From col ( $from_tt->{col} ) ne To coll ( $to_tt->{coll} )\n";
	      my $att = $schema->class($dest)->association($companion);
	      if ($schema_storage->id($att)) {
		  print "Fix ( set To coll to $from_tt->{col} ) ? ";
		  if (askyn()) {
		      my $att = $schema->class($dest)->association($companion);
		      if (!$att->options) {
			  $att->set_options({});
		      }
		      $att->options->{"coll"} = $from_tt->{col};
		      local($Tangram::TRACE) = \*STDOUT;
		      $schema_storage->update($att);
		  }
	      } else {
		  print "Can't fix, skipping\n";
	      }
	  }
      } elsif ($other_type eq "ref") {
	# a one to one mapping
	  print "Warning: Non-normal form in $class"."->$attribute\n";
      } else {
	print STDERR "Wierd schema!  $types->{$attribute} to $other_type!\n";
      }
    }

  }

}


sub askyn {
    print "[Y/N] ";
    return (<STDIN> =~ m/^y/i);
}
