#!/usr/bin/perl
use lib do {__FILE__ =~ /^(.*)[\/\\]/; ($1||'.').'//home/lewis/stash/git/palace'};
use MakePl;

my @programs = qw(
    action/view
);

subdep sub {
    my ($file) = @_;
    return () unless $file =~ /\.hs$/;
    my $text = slurp($file, 4096, 0) // return ();
    return map {
        my $f = 'lib/' . s/\./\//rsg . '.hs';
        -e $f ? $f : ()
    } $text =~ /^import\s*(?:qualified\s*)?([a-zA-Z0-9_'\.]*)/smg;
};

for my $p (@programs) {
    rule "$p.cgi", "$p.hs", sub {
        run "ghc -ilib '$p.hs' -o '$p.cgi'";
    }
}

rule 'clean', [], sub {
    for (@programs) { unlink "$_.cgi", "$_.hi", "$_.o"; }
};

make;
