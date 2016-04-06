#!/usr/bin/perl
use v5.18;
use bytes;

my @page_fields = qw(id created_at updated_at committed deleted prev_id path title html originated_at);
my @page_types = qw(INTEGER TEXT TEXT INTEGER INTEGER INTEGER TEXT TEXT TEXT TEXT);
my $page_fields = join ', ', @page_fields;

my @link_fields = qw(id deleted prev_id rel from_id to_id);
my @link_types = qw(INTEGER INTEGER INTEGER TEXT INTEGER INTEGER);
my $link_fields = join ', ', @link_fields;

sub new_page {
    my ($path) = @_;
    $path // confess "Undefined path argument given to new_page";
    require Time::HiRes;
    my $time = iso_time(Time::HiRes::gettimeofday());
    return {
        id => undef,
        created_at => $time,
        updated_at => undef,
        committed => 0,
        deleted => 0,
        prev_id => undef,
        prev_path => undef,
        path => $path,
        title => undef,
        html => undef,
        originated_at => undef,
        links => [],
        linked => [],
    };
}

sub get_page_by_condition {
    require lib::db;
    my ($edit, $bare, $condition, @params) = @_;

    my $page = db_sub("
        SELECT $page_fields, v.path AS prev_path FROM pages
        LEFT JOIN pages v ON v.id = prev_id
        WHERE ($condition) ".($edit ? "" : "AND committed = 1")."
        ORDER BY id DESC LIMIT 1
    ")->(@params)->fetchrow_hashref;
    $bare and return $page;
    defined $page or return $page;

    $page->{links} = [];
    my $lfs = join ', ', map "l.$_", @link_fields;
    my $pfs = join ', ', map "p.$_", @page_fields;
    my $links = db_sub(
        $edit ? "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN (
                SELECT $page_fields FROM pages
                WHERE path = l.to_path
                ORDER BY id DESC LIMIT 1
            ) AS p
            WHERE l.from_id = {INTEGER}
            ".($page->{committed} ? " AND NOT l.deleted" : "")."
            ORDER BY l.id
        " : "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN (
                SELECT $page_fields FROM pages
                WHERE path = l.to_path
                ORDER BY id DESC LIMIT 1
            ) AS p
            WHERE l.from_id = {INTEGER} AND NOT l.deleted AND NOT p.deleted AND p.id IS NOT NULL
            ORDER BY l.id
        "
    )->($page->{id});
    for my $row (@{$links->fetchall_arrayref}) {
        my $link = {to => {}};
        my $i = 0;
        for (@link_fields) {
            $link->{$_} = $row->[$i++];
        }
        for (@page_fields) {
            $link->{to}{$_} = $row->[$i++];
        }
        push @{$page->{links}}, $link;
    }

    my $linked = db_sub(
        $edit ? "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN pages p ON p.id = l.from_id
            WHERE l.to_id = {INTEGER} AND l.prev_id NOT IN (
                SELECT id FROM links WHERE to_id = l.to_id
            ) AND NOT l.deleted AND NOT p.deleted
            ORDER BY l.id
        " : "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN pages p ON p.id = l.from_id
            WHERE l.to_id = {INTEGER} AND l.prev_id NOT IN (
                SELECT l.id FROM links l
                LEFT JOIN pages p ON p.id = l.from_id
                WHERE to_id = l.to_id AND p.committed
            ) AND NOT l.deleted AND NOT p.deleted AND p.committed
            ORDER BY l.id
        "
    )->($page->{id});
    for my $row (@{$linked->fetchall_arrayref}) {
        my $link = {from => {}};
        my $i = 0;
        for (@link_fields) {
            $link->{$_} = $row->[$i++];
        }
        for (@page_fields) {
            $link->{from}{$_} = $row->[$i++];
        }
        push @{$page->{linked}}, $link;
    }
    return $page;
}

sub get_page_by_path {
    my ($path, $edit, $bare) = @_;
    return get_page_by_condition($edit, $bare, "p.path = {TEXT}", $path);
}

sub get_page_by_path_and_id {
    my ($path, $id, $edit) = @_;
    return get_page_by_condition($edit, $bare, "p.path = {TEXT} AND p.id = {INTEGER}", $path, $id);
}

sub get_page_by_id {
    my ($id, $edit, $bare) = @_;
    return get_page_by_condition($edit, $bare, "p.id = {INTEGER}", $id);
}

sub update_page {
    require lib::db;
    my ($page) = @_;
     # Validate and complete
    defined $page->{path} or e400 "Page is missing required field path.";
    defined $page->{created_at} or e400 "Page is missing required field created_at.";
    defined $page->{updated_at} and e400 "Page has forbidden field updated_at.";
    defined $page->{committed} or e400 "Page is missing required field committed.";
    defined $page->{deleted} or e400 "Page is missing required field deleted.";
    if (defined $page->{id}) {
        my $prev = get_page_by_id($page->{id}, 1, 1);
        defined $prev or e400 "Item referenced by id does not exist.";
        $page->{created_at} eq $old_page->{created_at}
            or e400 "New page's created_at does not match old page's.";
        $page->{prev} = $prev;
    }
    my $other_page = get_page_by_path($page->{path}, 1, 1);
    if (defined $other_page and $other_page->{id} != ($page->{prev_id} // 0)) {
        e400 "Path $page->{path} is already used by another page.";
    }
    for my $link (@{$page->{links}}) {
        defined $link->{rel} or e400 "Link is missing required field rel";
        defined $link->{to_path} or e400 "Link is missing requried field to_path";
        if (defined $link->{id}) {
            defined $page->{id} or e400 "Link id was given without page id.";
            my $old = db_sub("
                SELECT from_id FROM links WHERE id = {INTEGER} LIMIT 1
            ")->($link->{id})->fetchall_arrayref;
            @$old or e400 "Link id does not match any existing link.";
            $old->[0] == $page->{id} or e400 "Link from_id does not match page id.";
        }
        my $to = db_sub("
            SELECT $page_fields FROM pages WHERE path = {TEXT} ORDER BY id DESC LIMIT 1
        ")->($_->{to_path})->fetchrow_hashref;
        defined $to or die "Target of link to $_->{to_path} does not exist.";
        $_->{to} = $to;
    }
    require Time::HiRes;
    $page->{updated_at} = iso_time(Time::HiRes::gettimeofday());
    if (defined $page->{prev} and !$page->{prev}{committed}) {
         # Update
        my $fields = join ', ',
            map "$page_fields[$_] = {$page_types[$_]}",
            1..$#page_fields;
        db_sub("
            UPDATE pages SET $fields WHERE id = {INTEGER};
        ")->((map $page->{$_}, @page_fields[1..$#page_fields]), $page->{id});
        for my $link (@{$page->{links}}) {
        }
    }
    else {
         # Insert
        db_sub(
            "INSERT INTO pages (" . (join ', ', @page_fields[1..$#page_fields])
            . ") VALUES (" . (join ', ', map "{$_}", @page_types[1..$#page_fields]) . ")"
        )->(map $page->{$_}, @page_fields[1..$#page_fields]);
        $page->{id} = select_last_id();
        for my $link (@{$page->{links}}) {
            $page->{links}{from_id} = $page->{id};
            db_sub(
                "INSERT INTO links (" . (join ', ', @link_fields[$#link_fields])
                . ") VALUES (" . (join ', ', map "{$_}"< @link_types[1..$#link_fields]) . ")"
            )->(map $link->{$_}, @link_fields[1..$#link_fields]);
        }
    }
}
