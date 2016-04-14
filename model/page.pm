#!/usr/bin/perl
use v5.18;
use bytes;

my @page_fields = qw(id created_at updated_at committed obsolete prev_id path title html originated_at);
my @page_types = qw(INTEGER VARCHAR VARCHAR INTEGER INTEGER INTEGER VARCHAR TEXT TEXT VARCHAR);
my $page_select = join ', ', @page_fields;
my $page_insert_fields = join ', ', @page_fields[1..$#page_fields];
my $page_insert_types = join ', ', map "{$_}", @page_types[1..$#page_types];
my $page_update_set = join ', ',
    map "$page_fields[$_] = {$page_types[$_]}",
    1..$#page_fields;

my @link_fields = qw(id from_id rel to_path);
my @link_types = qw(INTEGER INTEGER VARCHAR VARCHAR);
my $link_select = join ', ', @link_fields;
my $link_insert_fields = join ', ', @link_fields[1..$#link_fields];
my $link_insert_types = join ', ', map "{$_}", @link_types[1..$#link_types];
my $link_update_set = join ', ',
    map "$link_fields[$_] = {$link_types[$_]}",
    1..$#link_fields;

my $page_output_schema = {
    id => 'int?!',
    created_at => 'str!',
    updated_at => 'str?!',
    committed => 'bool!',
    obsolete => 'bool!',
    prev_id => 'int?!',
    prev_path => 'path?!',
    path => 'path!',
    title => 'str?!',
    html => 'str?!',
    originated_at => 'str?!',
    links => [{
        id => 'int!',
        from_id => 'int!',
        rel => 'str!',
        to_path => 'path!',
        to => {
            '?' => 1,
            id => 'int!',
            created_at => 'str!',
            updated_at => 'str!',
            committed => 'bool!',
            obsolete => 'bool!',
            prev_id => 'int?!',
            path => 'path!',
            title => 'str?!',
            html => 'str?!',
            originated_at => 'str?!',
        },
    }, '!'],
    linked => [{
        id => 'int!',
        from_id => 'int!',
        rel => 'str!',
        to_path => 'path!',
        from => {
            id => 'int!',
            created_at => 'str!',
            updated_at => 'str!',
            committed => 'bool!',
            obsolete => 'bool!',
            prev_id => 'int?!',
            path => 'path!',
            title => 'str?!',
            html => 'str?!',
            originated_at => 'str?!',
        },
    }, '!'],
};

my $page_input_schema = {
    id => 'int?!',
    created_at => 'str?!',
    committed => 'bool!',
    path => 'path!',
    title => 'str?!',
    html => 'str?!',
    originated_at => 'str?!',
    links => [{
        rel => 'str!',
        to_path => 'path!',
    }, '!'],
};

sub new_page {
    my ($path) = @_;
    $path // confess "Undefined path argument given to new_page";
    require Time::HiRes;
    my $time = iso_time(Time::HiRes::gettimeofday());
    my $page = {
        id => undef,
        created_at => $time,
        updated_at => undef,
        committed => 0,
        obsolete => 0,
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
        SELECT $page_select FROM pages
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
                SELECT $page_select FROM pages
                WHERE path = l.to_path AND NOT p.obsolete
                ORDER BY id DESC LIMIT 1
            ) AS p
            WHERE l.from_id = {INTEGER}
            ORDER BY l.id
        " : "
            SELECT $lfs, $pfs FROM links l, pages p
            WHERE l.from_id = {INTEGER} AND p.path = l.to_path AND NOT p.obsolete AND p.committed
            ORDER BY l.id
        "  # Should always return one or zero rows per link, if the invariants are preserved
    )->($page->{id});
    for my $row (@{$links->fetchall_arrayref}) {
        my $link = {};
        my $i = 0;
        for (@link_fields) {
            $link->{$_} = $row->[$i++];
        }
        if (defined $row->[$i]) {  # Should be page id
            $link->{to} = {};
            for (@page_fields) {
                $link->{to}{$_} = $row->[$i++];
            }
        }
        push @{$page->{links}}, $link;
    }

    my $linked = db_sub(
        $edit ? "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN pages p ON p.id = l.from_id
            WHERE l.to_path = {VARCHAR} AND NOT p.obsolete
            ORDER BY l.id
        " : "
            SELECT $lfs, $pfs FROM links l
            LEFT JOIN pages p ON p.id = l.from_id
            WHERE l.to_path = {VARCHAR} AND NOT p.obsolete AND p.committed
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
    criticize_warn($page, $page_output_schema, "Output page failed schema test:");
    return $page;
}

sub get_page_by_path {
    my ($path, $edit, $bare) = @_;
    return get_page_by_condition($edit, $bare, "path = {TEXT} AND NOT obsolete", $path);
}

sub get_page_by_path_and_id {
    my ($path, $id, $edit, $bare) = @_;
    return get_page_by_condition($edit, $bare, "path = {TEXT} AND id = {INTEGER}", $path, $id);
}

sub get_page_by_id {
    my ($id, $edit, $bare) = @_;
    return get_page_by_condition($edit, $bare, "id = {INTEGER}", $id);
}

sub update_page {
    require lib::schema;
    my ($page) = @_;
     # Validate and complete
    criticize_die($page, $page_input_schema, "Page to update is not valid:");
    if (defined $page->{id}) {
        my $old = get_page_by_id($page->{id}, 1, 1);
        defined $old or e400 "Page referenced by id does not exist.";
        if ($old->{committed}) {
            e400 "Cannot overwrite an already committed page.";
        }
        $page->{old} = $old;
        if (defined $page->{created_at}) {
            e400 "Page cannot have both created_at and id.";
        }
        else {
            $page->{created_at} = $old->{created_at};
        }
    }
    elsif (defined $page->{created_at}) {
        e400 "Page must have either id or created_at.";
    }
    my $other = get_page_by_path($page->{path}, 1, 1);
    if (defined $other and $page->{id} != $other->{id} and !$other->{deleted}) {
        e400 "Page's path is already used by another page.";
    }
    require lib::db;
    for my $link (@{$page->{links}}) {
        $link->{from_id} = $page->{id};
    }
    require Time::HiRes;
    $page->{updated_at} = iso_time(Time::HiRes::gettimeofday());
    if (defined $page->{old} and !$page->{old}{committed}) {
         # Update
        db_sub("
            UPDATE pages SET $page_update_set WHERE id = {INTEGER}
        ")->((map $page->{$_}, @page_fields[1..$#page_fields]), $page->{id});
        db_sub("DELETE FROM links WHERE from_id = {INTEGER}")->($page->{id});
        for my $link (@{$page->{links}}) {
            db_sub("
                INSERT INTO links ($link_insert_fields) VALUES ($link_insert_types)
            ")->(map $link->{$_}, @link_fields[1..$#link_fields]);
        }
    }
    else {
         # Insert
        db_sub("
            INSERT INTO pages ($page_insert_fields) VALUES ($page_insert_types)
        ")->(map $page->{$_}, @page_fields[1..$#page_fields]);
        $page->{prev_id} = $page->{id};
        $page->{id} = select_last_id();
        for my $link (@{$page->{links}}) {
            db_sub(
                "INSERT INTO links (" . (join ', ', @link_fields[$#link_fields])
                . ") VALUES (" . (join ', ', map "{$_}"< @link_types[1..$#link_fields]) . ")"
            )->(map $link->{$_}, @link_fields[1..$#link_fields]);
        }
    }
    if ($page->{committed} and defined $page->{prev_id}) {
        db_sub(
            "UPDATE pages SET obsolete = 1 WHERE id = {INTEGER}"
        )->($page->{prev_id});
    }
}
