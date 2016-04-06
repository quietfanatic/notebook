use v5.18;
use bytes;

sub e400 {
    print "Status: 400 Bad Request\n";
    print "Content-Type: text/plain; charset=UTF-8\n\n";
    print @_;
    print "\n";
    exit 1;
};
sub e500 {
    print "Status: 500 Internal Server Error\n";
    print "Content-Type: text/plain; charset=UTF-8\n\n";
    print @_;
    print "\n";
    exit 1;
};
sub die_html {
    print "<!-- ERROR --><div class=\"internal-error\">@_</div>";
    die @_;
};

BEGIN {
    $SIG{__DIE__} = sub {
        e500 @_ unless $^S;
        die @_;
    };
    $SIG{__WARN__} = sub {
        push @::warnings, join '', @_;
        warn @_;
    };
}

sub done_with_headers {
    $SIG{__DIE__} = sub {
        die_html @_ unless $^S;
        die @_;
    };
}

sub confess {
    require Carp;
    goto &Carp::confess;
}

sub slurp {
    local $/;
    open my $F, '<', $_[0] or confess "Couldn't open $_[0] for reading: $!\n";
    my $r = <$F> // confess "Couldn't read from $_[0]: $!\n";
    close $F or confess "Couldn't close $_[0]: $!\n";
    return $r;
}

sub unesc_uri {
    return $_[0] =~ s/\+/ /gr =~ s/%([0-9a-zA-Z]{2})/chr hex $1/egr;
}
sub esc_uri {
    return $_[0] =~ s/([!*'();:@&=+$,\/?#\[\]])/sprintf "%%%02X", ord $1/egr;
}
sub esc_html {
    my %esc = (
        '&' => '&amp;',
        '<' => '&lt;',
        '>' => '&gt;',
        '"' => '&quot;',
        "'" => '&apos;',
    );
    return $_[0] =~ s/([&<>"'])/$esc{$1}/egr;
}
sub iso_time {
    my ($s, $us) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($s);
     # Kind of a silly algorithm to get the time zone, but I believe it works in all cases.
     # Days of the week don't change in different zones, right?  Right?
    my (undef,$gmtmin,$gmthour,undef,undef,undef,$gmtwday) = gmtime($s);
    my $diff = ($min + $hour * 60 + $wday * 1440)
             - ($gmtmin + $gmthour * 60 + $gmtwday * 1440);
    if ($diff > 3 * 1440) {  # 適当
        $diff -= 7 * 1440;
    }
    elsif ($diff < -3 * 1440) {
        $diff += 7 * 1440;
    }
    my $usf = defined($us) ? '.%06d' : '';
    return sprintf "%04d-%02d-%02dT%02d:%02d:%02d$usf%+03d:%02d",
        $year + 1900, $mon + 1, $mday, $hour, $min, $sec, defined($us) ? $us : (),
        int($diff / 60), abs($diff) % 60;
}

sub get_params {
    my %param;
    if ($ENV{REQUEST_METHOD} eq 'POST') {
        local $/ = \102400;
        my $text = <STDIN>;
        for (split /[&;]/, $text) {
            /^([^=]*)(?:=(.*))$/;
            $param{unesc_uri($1)} = unesc_uri($2);
        }
    }
    elsif ($ENV{REQUEST_METHOD} eq 'GET') {
        for (split /[&;]/, $ENV{QUERY_STRING}) {
            /^([^=]*)(?:=(.*))$/;
            $param{unesc_uri($1)} = unesc_uri($2);
        }
    }
    else {  # Read from command line
        for (@ARGV) {
            /^([^=]*)(?:=(.*))$/;
            $param{unesc_uri($1)} = unesc_uri($2);
        }
    }
    while (@_) {
        my $name = shift;
        my $match = shift;
        if (ref $match eq 'Regexp') {
            if (exists $param{$name}) {
                '' =~ $match or e400 "No $name in parameters.";
            }
            else {
                $param{$name} =~ $match or e400 "Invalid $name=$param{$name} in parameters.";
            }
        }
        elsif (ref $match eq 'ARRAY') {
            if (exists $param{$name}) {
                grep {
                    $_ ne '?' and $param{$name} eq $_
                } @$match or e400 "Invalid $name=$param{$name} in parameters; allowed values are <@$match>.";
            }
            else {
                grep $_ eq '?', @$match or e400 "No $name in parameters.";
            }
        }
        elsif ($match =~ /^int(\?)?$/) {
            if (exists $param{$name}) {
                $param{$name} =~ /^[0-9]*$/ or e400 "Parameter $name=$param{$name} isn't an integer.";
                $param{$name} += 0 unless $param{$name} eq '';
            }
            else {
                $1 or e400 "No $name in parameters.";
            }
        }
        elsif ($match =~ /^str(\?)?$/) {
            $1 or exists $param{$name} or e400 "No $name in parameters.";
        }
        else {
            e500 "Invalid parameter in validate_params.";
        }
    }
    return %param;
}

1;
