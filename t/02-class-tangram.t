#!/usr/bin/perl -w

# This test suite converts a Class::Tangram schema to a T2::Class &
# associated objects.

use lib "../lib";

use Test::More tests => 11;
use T2::Schema;

my $schema = new T2::Schema ( site_name => "schema" );

eval {
    local($^W)=0;
    $schema->add_class_from_schema(Class => "foobar")
};
isnt($@, "", "Anti-GIGO check 1a");
is($schema->class_exists("Class"), undef, "Anti-GIGO check 1b");

$schema->add_class_from_schema("T2::$_" => ${"T2::${_}::schema"})
    foreach qw(Class Attribute Association Method Schema);

is($schema->classes(0)->name, "T2::Class",
   "Classes made it into the schema");

my @associations = $schema->classes(0)->associations;

isnt(scalar(@associations), 0,
     "Associations made it into the schema");

isa_ok($associations[0], "T2::Association", "Association of Class");

SKIP: {
    eval "use T2::Storage"; die $@ if $@;

    my $schema_storage;
    eval {
	$schema_storage = T2::Storage->open("t/T2");
    };
    skip "Schema DB connect failed ($@)", 6 if $@;
    pass("connection opened to storage");

    eval {

	my $schema_r = $schema_storage->remote("T2::Schema");
	my @toast = $schema_storage->select
	    ( $schema_r,
	      $schema_r->{site_name} eq "schema"
	    );
	$schema_storage->erase(@toast);
	$schema_storage->unload_all();

    };

    # hack - think of a better way to deal with this later
    $schema->class("T2::Schema")->attribute("normalize_sub")->options->{init_default} = undef;

    my $oid = $schema_storage->insert($schema);
    ok($oid, "Schema for T2::Schema inserted to database");

    my $class = $schema->classes(0);
    #diag ("Class is ".$class->quickdump);
    ok($schema_storage->id($class),
       "A `random' class has an ID in storage");
    my $assoc = $class->get_associations(1);
    #diag ("Association is ".$assoc->quickdump);
    ok($oid = $schema_storage->id($assoc),
       "A `random' association has an ID in storage");

    ok($schema_storage->oid_isa($oid, "T2::Association"),
       "->oid_isa()");

    my @classes = $schema_storage->select( "T2::Class" );

    is(@classes, $schema->classes_size,
       "Only the classes we inserted exist");

};
