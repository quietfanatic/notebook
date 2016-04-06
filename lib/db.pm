#!/usr/bin/perl
use v5.18;
use bytes;

my $db;
sub get_db {
    defined $db and return $db;
    require DBI;
    -e 'db/db.sqlite3' or die "No database file found.\n";
    $db = DBI->connect("dbi:SQLite:dbname=db/db.sqlite3","","",{
        RaiseError=>1,
        AutoCommit=>0
    });
    return $db;
}

sub db_sub {
    require DBI;
    no strict 'refs';
    my ($sql) = @_;
    my @types;
    $sql =~ s/\{([A-Z]+)\}/push @types, $1 eq 'TEXT' ? DBI::SQL_VARCHAR() : &{"DBI::SQL_$1"}(); '?'/eg;
    my $st = get_db()->prepare($sql);
    return sub {
        @_ == @types or confess "Incorrect number of parameters given to db sub (".(0+@_)." != ".(0+@types).")";
        for (0..$#types) {
            $st->bind_param($_+1, $_[$_], $types[$_]);
        }
        $st->execute;
        return $st;
    };
}

sub select_last_id {
    return get_db()->selectall_arrayref("SELECT last_insert_rowid();")->[0][0];
}

1;
