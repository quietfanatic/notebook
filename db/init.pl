#!/usr/bin/perl
use v5.18;
use warnings;
use bytes;
BEGIN { chdir(__FILE__ =~ /^(.*)\// ? "$1/.." : "..") or die "Could not chdir: $!\n"; }

open my $schema, '<', 'db/schema.sql' or die "Could not open db/schema.sql: $!\n";
local $/ = ';';
my @statements = <$schema>;
close $schema or die "Could not close db/schema.pl: $!\n";

use DBI qw(:sql_types);
my $db = DBI->connect("dbi:SQLite:dbname=db/db.sqlite3","","",{
    RaiseError=>1,
    AutoCommit=>0,
});
!system(qw(setfacl -m user:www-data:rw db/db.sqlite3))
    or die "Could not setfacl db/db.sqlite3: $!\n";

$db->do($_) for @statements;
$db->commit;

print "Database successfully initialized.\n";
