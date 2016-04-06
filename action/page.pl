#!/usr/bin/perl
use v5.18;
use warnings;
use bytes;
BEGIN { chdir(__FILE__ =~ /^(.*)\// ? "$1/.." : "..") or die "Could not chdir: $!\n"; }
use lib '.';
use lib::cgi;
use model::page;

if (exists $ENV{REQUEST_METHOD} and $ENV{REQUEST_METHOD} ne 'GET') {
    e500 "POST NYI.";
}
my %P = get_params(
    id => 'int?',
    DEBUG => 'int?',
);

if (exists $P{DEBUG}) {
    print "Content-Type: text/plain; charset=UTF-8\n\n";
    for (keys %ENV) {
        print "$_ => $ENV{$_}\n";
    }
    print __FILE__, "\n";
    print "$0\n";
    exit 0;
}

my $me = "action/page.pl";

$ENV{SCRIPT_NAME} =~ /^(.*)\/\Q$me\E$/
    or die "Confused because SCRIPT_NAME didn't end with $me.";
my $base = $1;
exists $ENV{REDIRECT_URL}
    or die "Confused because not running under Apache mod_rewrite.";
$ENV{REDIRECT_URL} =~ /^\Q$base\E\/(.*)$/
    or die "Confused because SCRIPT_NAME and REDIRECT_URL were too different.";
my $path = $1;

if (defined $P{id}) {
    my $page = get_page_by_path_and_id($path, $P{id}, 0);
    render_page($page, 0);
}
else {
    my $page = get_page_by_path($path, 1);
    if (defined $page) {
        render_page($page, 1);
    }
    else {
        render_page(new_page($path), 1);
    }
}

sub render_page {
    my ($page, $edit) = @_;
    defined $page or e404();
    print "Content-Type: text/html; charset=UTF-8\n\n";
    done_with_headers;
    require lib::template;
    print_template('{@view/page.html@}', {
        edit => $edit,
        base => $base,
        page_title => ($page->{title} // $page->{path}) . ($page->{finalized} ? '' : ' (new)'),
        date => $page->{originated_at} // $page->{created_at},
        id => $page->{id} // "(undefined)",
        created_at => $page->{created_at},
        updated_at => $page->{updated_at} // "(undefined)",
        prev_id => $page->{prev_id},
        prev_path => $page->{prev_path},
        deleted => $page->{deleted},
        path => $page->{path},
        title => $page->{title} // ($edit ? "(untitled)" : $page->{path}),
        html => $page->{html} // "<p>(no content)</p>",
        originated_at => $page->{originated_at} // "(undefined)",
        links => [map {({
            rel => $_->{rel},
            to => $_->{page}{path},
        })} @{$page->{links}}],
        linked => [map {({
            rel => $_->{rel},
            from => $_->{page}{path},
        })} @{$page->{linked}}],
        warnings => sub { \@::warnings },
    });
}

sub e404 {
    print "Status: 404 Not Found\n";
    print "Content-Type: text/html; charset=UTF-8\n\n";
    done_with_headers;
    require Time::HiRes;
    require lib::template;
    print_template('{@view/404.html@}', {
        date => iso_time(Time::HiRes::gettimeofday()),
        warnings => sub { \@::warnings },
    });
    exit 0;
}
