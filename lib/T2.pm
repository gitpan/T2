package T2;
use vars qw($VERSION);
$VERSION = 0.07;

 WumpT

__END__

=head1 NAME

T2 - Object Relational mapping system

=head1 SYNOPSIS

  use T2::Storage;

  # T2::Storage class provides Tangram::Storage API and
  # loads schemas
  my $storage = T2::Storage->open("appName");
  my (@ids) = $storage->insert(@some_objects);

  # T2::Schema structures can be manipulated in the same way
  my $schema_storage = T2::Storage->open("schema");
  my $schema = T2::Schema->load("appName", $schema_storage);
  my @classes = $schema->classes;
  $schema->classes_remove(17);    # remove a random class
  $schema_storage->update($schema);

=head1 DESCRIPTION

The T2 module is a base for the refactoring of the now quite stable
Tangram Object-Relational mapper.

In a nutshell, it lets you store objects - which have to be described
to a similar level that you would describe a database to store them -
into any SQL store.  Currently, this is tested on PostgreSQL, MySQL,
Oracle and Sybase a lot, though in general database-specific
extensions to SQL, such as triggers, stored procedures, etc are
avoided.  So, if DBI installs and tests successfully with your
database, there is a good chance that T2 will work with it too.

The only current requirement is that objects that have tables
associated with them are implemented via hashes.  You also have to be
able to describe all of the fields for those root objects.  Individual
fields of stored objects may be arbitrarily complex.

If you are familiar with DBI, it is somewhat similar to bless'ing the
structures returned by C<$dbh-E<gt>fetchrow_hashref>, except that
references and collections to other objects in the store are loaded
`on demand' (aka Lazy-loading).

=head1 CONTENTS

The T2:: namespace currently contains:

=over

=item B<T2::Storage>

T2::Storage is a convenience wrapper for Tangram::Storage.  Hence, the
object it returns provides the complete Tangram 2 API.  It contains a
constructor that automatically grabs configuration information (such
as, database location, schema details, etc), and connects to the
database.

It makes simple programs, for existing applications that have an
established schema very simple.  Getting the schema structures there
in the first place, however, is not terribly straightforward.  Yet.

As more of the Tangram core is ported over the the new T2::Storage
class, the documentation here and in L<T2::Storage> will be completed.
For now, L<Tangram> and L<Tangram::Storage> are the best starting
points.

=item B<T2::Schema>, B<T2::Class>, etc.

The T2::Schema structures are the Tangram schema, expressed as
Class::Tangram objects.  These are hence easily storable in a T2 data
store.  Or a Pixie/MLDBM/etc store, for that matter.

=back

=head1 FREQUENTLY UNASKED QUESTIONS (FUQ)

You might be asking, "how does one write a FUQ file?"

One answer is by becoming maintainer of a module, and talking to
people who have looked at a module, and seeing what drawbacks they
saw, or why they didn't take it any further.

=over

=item B<How do I just quickly store an object?>

At the moment, there is no shortcut.  You must declare a simple schema
that has the object type (or one of its superclasses) that you wish to
store.

B<Warning:> the examples in this section have been quickly written,
and there are probably some minor bugs.  If you encounter problems,
please send a message to the mailing list (see L<SUPPORT>).

Creating this structure is a lot easier with the
I'll-release-it-RSN-ware web-based VT2 tool, but here is some example
code to set up a schema file;

  my $schema = T2::Schema->new
      ( T2::Class->new( name => "ExampleClass",
                        attributes => [ T2::Attribute->new
                                        ( type => "perl_dump",
                                          name => "foo",
                                        ) ],
      );

  use Storable qw(freeze);
  open FOO, ">etc/myApp.t2";
  binmode FOO;
  $Storable::Deparse = 1;
  print FOO freeze $schema;
  close FOO;

Yes, OK, that's not exactly a one-liner.  But it should give you an
idea of what's involved.  Again, the web-based tool to manage the
above schema structures makes things a lot quicker.

You'd then create a file F<etc/myApp.dsn>, with something like the
following contents:

  dsn dbi:mysql:database=myApp
  user myApp
  auth razamatazz
  schema myApp

(yes, this should be YAML.  Patches welcome :))

Then, you need to create the user and set up the database.  You can
use the F<t2-migrate-db.pl> utility script in the T2 distribution
to do the latter;

  $ echo 'grant all privileges on myApp.* to myApp@localhost' \
              identified by "razamatazz"' | mysql -uroot -p
  Password:
  $ t2-migrate-db.pl --read --deploy myApp
  ...
  $

Still with me?  Good.  Then the script to actually I<use> the code is
simple;

  use T2::Storage;
  my $storage = T2::Storage->open("myApp");

  # this line makes the classes for you, if you didn't
  # already have ExampleClass written.
  $storage->schema->generator();

  # stick an object in the DB and return an object ID
  my $oid = $storage->insert(new ExampleClass(foo => "bar"));

  # anything in $exampleClass->foo can be stored (via
  # perl_dump mapping)
  use Whatever;

  # fetch the object back
  my $exampleClass = $storage->load($oid);
  $exampleClass->set_foo( { bar => new Whatever() } );
  $storage->update($exampleClass);

  $storage->insert(new ExampleClass
                        (foo => [ 1, 2, $exampleClass ]));

See L<Tangram::Tour> for a more detailed example of how to manipulate
objects in the database, and L<Class::Tangram> for more information on
how to use the generated constructors and accessors (eg, C<new
ExampleClass> and C<set_foo> in the above example).

You don't I<have> to use Class::Tangram classes in a T2 store.  But
they are very well behaved OO classes that communicate via message
passing exclusively, and export the information needed by T2 to store
them in a package global.  So they're convenient.

=item B<How do I just quickly get an object out?>

If you still have the object ID, you can fetch it by that;

  my $user = $storage->load($user_oid);

If that user has a reference to another storage object in it (what
would normally be accomplished using an ID into another table in SQL),
then you can just access the value; it is `demand paged' / `lazy
loaded' via Data::Lazy or an equivalent.  For example;

  my $details = $user->details;

If the referant object is already in memory, then the in-memory
version is used instead of being explicitly loaded from the database.

Otherwise, you can use the OO query format explained in much more
detail in L<Tangram::Tour>;

  my $remote_session = $storage->remote("MySession::Class");
  my ($session) = $storage->select
                     ($remote_session,
                      $remote_session->{SID} eq $somesid);

The query format is flexible enough to represent virtually any SQL
query.  The "$remote_session" object is an object which represents an
object in the database of the given type.  So, the expression
C<$remote_session->{SID} eq $somesid> returns an object that
represents all MySession::Class objects that have a "SID" of $somesid.

Generally, people either think that this syntax is the cleanest method
of expressing relationships in a non-SQL way possible, or, as one of
the Pixie authors put it, you 'turn running and screaming'.

=item B<OK, now how do I change the schema?>

Simply write a new F<etc/myApp.t2> schema file.  Modify the script
above and re-run it.

=item B<How does Tangram compare to XXX?>

First, you should have a look at the POOP (that's Perl Object Oriented
Persistence C<:)>) summary at L<http://poop.sf.net/>.

In a nutshell, there are two types of persistence tools; SQL
abstractors (eg, Alzabo, Class::DBI) and true Object Persistence tools
(eg Pixie, Tangram).

The SQL abstractors tend to require that all of your objects derive
from a common base class.  This is encouraged with T2, but not
required.

The Object Persistence tools will generally let you store pretty much
anything, without `intruding' on your objects.  In theory, this means
that they may easily be loaded from one storage class and thrown into
another.

=item B<What Query languages do I use?>

See L<Tangram::Tour> for a run-down on the query format.

=item B<How can I manage schemas?>

Using the web-based tool that manages these T2::Schema data structures
in a Tangram store, and the supplied utility scripts.  The web-based
application is expected to be released by Q2 2004.

=item B<Why bother with schema maintenance at all?>

At some level, your application has a schema governing it.

The idea with these modules is that you express it all in a standard
way in one place, rather than keeping some in your head, some in the
module source, some in the database tables...

=item B<Wouldn't it be faster to roll your own indexes?>

There is an argument that it is simpler to opt for *very* simple data
persistence, and just use your own objects for the indexes.

The answer is, this really sucks for concurrency and transaction
safety.  Especially as the size of the index grows.  This is one of
the reasons you might want to use a database in the first place :-).

=back

=head1 SUPPORT

Support for bugs is provided on a "politely state your problem with a
test case to demonstrate the bug, and if you're lucky, someone will
fix it for you" basis.

To subscribe to the (currently fairly low volume) mailing list, see
L<http://www.perlfect.com/mailman/listinfo/tangram-t2-maintainers>.

=head1 CREDITS / AUTHOR

Jean-Louis Leroy is the original author of Tangram 1 and 2.

Sam Vilain is the author of T2::* and Class::Tangram, and current
maintainer of Tangram.

Changes are known to be contributed to the combined Tangram and T2
code base from:

  - Gabor Herr
  - Marian Kelc
  - Aaron Mackey
  - Kurt Stephens
  - Kate Pugh

=head1 LICENSE

Most of the code in this collection is dual GPL / Perl Artistic
license.  However, at least some of it is purely GPL.  So, the
combined license of this collection is currently the GPL.

For information on the GPL, please see L<http://www.gnu.org/>.

=cut
