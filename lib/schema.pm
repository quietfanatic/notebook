#!/usr/bin/perl
use v5.18;
use bytes;

##### This provides a simple validation method for data structures.

sub arity_miss {
    my ($got, $wanted) = @_;
    my (undef, undef, undef, $name) = caller 1;
    return $got > $wanted
        ? "Too many parameters passed to $name ($got > $wanted)"
        : "Too few parameters passed to $name ($got < $wanted)";
}
sub schema_char {
    my ($schema, $char) = @_;
    return ref $schema eq 'HASH' ? exists $schema->{$char}
         : ref $schema eq 'ARRAY' ? @$schema >= 2 && index($schema->[1], $char) != -1
         : index($schema, $char) != -1;
}

 # Returns list of strings.
sub criticize {
    my ($obj, $schema, $loc) = @_;
    @_ < 2 and croak arity_miss 0+@_, 2;
    @_ < 3 and $loc = 'TOP' if @_ < 3;
    @_ > 3 and croak arity_miss 0+@_, 3;
    if (!defined $schema) {
        return "Schema itself is broken at $loc";
    }
    elsif (!defined $obj) {
        schema_char($schema, '?') or return "Value at $loc should not be null";
        return ();
    }
    elsif (ref $schema eq 'HASH') {
        ref $obj eq 'HASH' or return "Value at $loc is not an object";
        my @errs;
        for (grep schema_char($schema->{$_}, '!'), keys %$schema) {
            next if /^[!?*&]$/;
            if (!exists $obj->{$_}) {
                push @errs, "Missing required property $_ at $loc";
            }
        }
        for (keys %$obj) {
            if (exists $schema->{$_}) {
                if (/^[!?*&]$/) {
                    push @errs, "Invalid property name $_ at $loc";
                }
                push @errs, criticize($obj->{$_}, $schema->{$_}, "$loc.$_");
            }
            elsif (exists $schema->{'*'}) {
                push @errs, criticize($obj->{$_}, $schema->{'*'}, "$loc.$_");
            }
            else {
                push @errs, "Unallowed property $_ at $loc";
            }
        }
        if (exists $schema->{'&'}) {
            push @errs, $schema->{'&'}($obj, $loc);
        }
        return @errs;
    }
    elsif (ref $schema eq 'ARRAY') {
        ref $obj eq 'ARRAY' or return "Value at $loc is not an array";
        my @errs;
        for (0..$#$obj) {
            push @errs, criticize($obj->[$_], $schema->[0], "$loc\[$_]");
        }
        return @errs;
    }
    elsif ($schema =~ /path/) {
        ref $obj eq '' or return "Value at $loc is not a string, let alone a path";
        my @errs;
        if ($obj eq '') {
            push @errs, "Value at $loc is too empty to be a path";
        }
        if (length $obj > 200) {
            push @errs, "Value at $loc is too long in bytes to be a path (".length($obj)." > 200)";
        }
        if ($obj =~ /^\s/) {
            push @errs, "Value at $loc has leading whitespace, and so cannot be a path";
        }
        if ($obj =~ /\s$/) {
            push @errs, "Value at $loc has trailing whitespace, and so cannot be a path";
        }
        if ($obj =~ /[\x00-\x1f\x7f]/) {
            push @errs, "Value at $loc contains unprintable characters not allowed in a path";
        }
        return @errs;
    }
    elsif ($schema =~ /timestamp/) {
        ref $obj eq '' or return "Value at $loc is not a string, let alone a timestamp";
        $obj =~ /^\d\d\d\d-\d\d-\d\d_\d\d-\d\d-\d\d_\d\d\d\d\d\d$/
            or return "Value at $loc does not look like a timestamp";
        return ();
    }
    elsif ($schema =~ /uri/) {
        ref $obj eq '' or return "Value at $loc is not a string, let along a uri";
        $obj =~ /^[a-z]+:\/\// or return "Value at $loc does not look like a uri";
        return ();
    }
    elsif ($schema =~ /string/) {
        ref $obj eq '' or return "Value at $loc is not a string";
         # Not caring about numbers
        return ();
    }
    elsif ($schema =~ /integer/) {
        ref $obj eq '' or return "Value at $loc is not a scalar, let alone an integer";
        $obj =~ /^\d+$/ or return "Value at $loc is not an integer";
        return ();
    }
    elsif ($schema =~ /bool/) {
        $obj =~ /^[01]$/ or return "Value at $loc is not 0 or 1";
        return ();
    }
    elsif ($schema =~ /\*/) {
        return ();  # Anything goes
    }
    else {
        return "Schema itself is broken at $loc";
    }
}
sub criticize_die {
    my ($obj, $schema, $mess) = @_;
    @_ == 3 or croak arity_miss 0+@_, 3;
    my @errs = criticize $obj, $schema;
    if (@errs) {
        die join("\n    ", $mess, @errs) . "\n";
    }
}
sub criticize_warn {
    my ($obj, $schema, $mess) = @_;
    @_ == 3 or croak arity_miss 0+@_, 3;
    my @errs = criticize $obj, $schema;
    if (@errs) {
        warn join("\n    ", $mess, @errs) . "\n";
    }
}
