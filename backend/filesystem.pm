#!/usr/bin/perl
package backend::filesystem;
use v5.18;
use warnings;
use bytes;  # Assume everything is UTF-8
use JSON::MaybeXS ':all';
use Time::HiRes;
sub croak { require Carp; goto &Carp::croak; }
sub clone { require Clone; goto &Clone::clone; }

our @EXPORT_OK = qw(
    null true false slurp splat
    now now_hires timestamp
    criticize criticize_die
    item_schema blank_item event_schema index_schema
    READ WRITE transaction item event item_event item_event_previous
    all_names all_items validate_everything
);
sub import {
    no strict 'refs';
    my @args = @_;
    shift @args;
    if (@args == 1 and $args[0] eq ':all' || $args[0] eq ':ALL') {
        @args = @EXPORT_OK;
    }
    my ($package, $file, $line) = caller;
    for my $a (@args) {
        grep $_ eq $a, @EXPORT_OK or croak "No export \"$a\" from palace";
        *{$package.'::'.$a} = \&{$a};
    }
}

sub null () { undef }
sub true () { JSON->true }
sub false () { JSON->false }

 # Overridden for testing
our $datadir = 'data';
our $test_time;


##### Misc utilities
sub arity_miss {
    my ($got, $wanted) = @_;
    my (undef, undef, undef, $name) = caller 1;
    return $got > $wanted
        ? "Too many parameters passed to $name ($got > $wanted)"
        : "Too few parameters passed to $name ($got < $wanted)";
}

sub slurp {
    my ($fn) = @_;
    @_ == 1 or croak arity_miss 0+@_, 1;
    local $/;
    open my $F, '<', $fn or die "Failed to open $fn for reading: $!\n";
    my $s = <$F> // die "Failed to read from $fn: $!\n";
    close $F or die "Failed to close $fn: $!\n";
    return $s;
}

sub splat {
    my ($fn, $str) = @_;
    @_ == 2 or croak arity_miss 0+@_, 1;
    open my $F, '>', $fn or die "Failed to open $fn for writing: $!\n";
    print $F $str or die "Failed to write to $fn: $!\n";
    close $F or die "Failed to close $fn: $!\n";
}

sub mkdirs {
    for (@_) {
        next if -d $_;
        mkdir $_ or die "Failed to mkdir $_: $!\n";
        chmod 0770, $_ or die "Failed to chmod $_: $!\n";
    }
}

sub now { defined $test_time ? $test_time++ : time }
sub now_hires { defined $test_time ? ($test_time++, 123456) : Time::HiRes::gettimeofday() }
sub timestamp {
    my ($s, $us) = @_ > 0 ? @_ : now_hires();
    my @t = gmtime($s);
    if (defined $us) {
        return sprintf '%04d-%02d-%02d_%02d-%02d-%02d_%06d',
            $t[5]+1900, $t[4]+01, $t[3], $t[2], $t[1], $t[0], $us;
    }
    else {
        return sprintf '%04d-%02d-%02d_%02d-%02d-%02d',
            $t[5]+1900, $t[4]+01, $t[3], $t[2], $t[1], $t[0];
    }
}


##### Validation

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
        is_bool($obj) and return "Value at $loc is a boolean, not an integer";
        $obj =~ /^\d+$/ or return "Value at $loc is not an integer";
        return ();
    }
    elsif ($schema =~ /bool/) {
        is_bool($obj) or return "Value at $loc is not a boolean";
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


##### Items

our $item_schema = {
    '?' => true,  # Deleted if null
    path => 'path!',
    title => 'string',
    links => [{
        rel => 'string!',
        path => 'path!',
        credit => 'integer',  # Into credits array
    }],
    contents => [{
        rel => 'string!',
        text => 'string',
        html => 'string',
        filename => 'string',
        origin => 'uri',
        originated_at => 'timestamp',
        downloaded_at => 'timestamp',
        origin_auth => 'string',
        credit => 'integer',  # Into credits array
    }],
    default_view => 'string',
    credits => [{
         # If has an item, will be in links
        name => 'string',
        uri => 'string',
        email => 'string',
        notify_approval => 'bool',  # Only valid for uploader
        notify_reply => 'bool',
    }],
    uploader => 'integer',
    access => {  # All false by default
        public => 'bool',  # More specific permissions will be in links
        visible => 'bool',  # If not true, unauthorized queries will 404
    },
    misc => { '*' => '*?' },  # Probably unneeded, but whatever.
     # Things not manually writable (changes will be reverted)
    auto => {
        '!' => true,
        created_at => 'timestamp!',
        changed_at => 'timestamp!',  # Only tracks manual changes (nothing in auto)
        linked => ['path', '!'],
    },
    '&' => sub {
        my @errs;
        if (exists $_[0]{uploader}) {
            push @errs, "Value at TOP.uploader is out of range for credits array"
                if $_[0]{uploader} < 0
                || $_[0]{uploader} >= @{$_[0]{credits}};
        }
        if (exists $_[0]{links}) {
            for (0..$#{$_[0]{links}}) {
                exists $_[0]{links}[$_]{credit} or next;
                push @errs, "Value at links[$_].credit is out of range for credits array"
                    if $_[0]{links}[$_]{credit} < 0
                    || $_[0]{links}[$_]{credit} >= @{$_[0]{credits}};
            }
        }
        if (exists $_[0]{contents}) {
            for (0..$#{$_[0]{contents}}) {
                exists $_[0]{contents}[$_]{credit} or next;
                push @errs, "Value at contents[$_].credit is out of range for credits array"
                    if $_[0]{contents}[$_]{credit} < 0
                    || $_[0]{contents}[$_]{credit} >= @{$_[0]{credits}};
            }
        }
        return @errs;
    },
};
sub item_schema () { $item_schema }

sub blank_item {
    my ($path) = @_;
    @_ == 1 or croak arity_miss 0+@_, 1;
    defined $path or croak "Path given to blank_item is undefined.";
    return {
        path => $path,
    };
};

sub deep_equals {
    my ($a, $b) = @_;
    ref $a ne ref $b and return 0;
    if (ref $a eq 'HASH') {
        for (keys %$a) {
            return 0 unless exists $b->{$_};
        }
        for (keys %$b) {
            return 0 unless exists $a->{$_};
            return 0 unless exists $a->{$_} and deep_equals($a->{$_}, $b->{$_});
        }
        return 1;
    }
    elsif (ref $a eq 'ARRAY') {
        return 0 unless @$a == @$b;
        for (0..$#$a) {
            return 0 unless deep_equals($a->[$_], $b->[$_]);
        }
        return 1;
    }
    elsif (defined $a) {
        return defined $b && $a eq $b;
    }
    else {
        return !defined $b;
    }
}

sub process_changes {
    my ($new, $old) = @_;
    if (!defined $new) {
        if (!defined $old) {
            return 0;
        }
         # TODO: delete
    }
    if (defined $old) {
        $new->{auto} = $old->{auto};
        return 0 if deep_equals($new, $old);
        $new->{auto}{changed_at} = timestamp;
        criticize_die $new, $item_schema, "Changed item $new->{path} did not pass validation.";
         # TODO: link tags
    }
    else {
        $new->{auto}{changed_at} =
        $new->{auto}{created_at} = timestamp;
         # TODO: link tags
        $new->{auto}{linked} = [];
        criticize_die $new, $item_schema, "Created item $new->{path} did not pass validation.";
    }
    return 1;
}


##### Backend

our $event_schema = {
    id => 'string!',
    started_at => 'timestamp!',
    finished_at => 'timestamp!',
    source => {
        '!' => true,
        interface => 'string!',
        '*' => '*?',
    },
    request => '*?!',
    response => '*?!',
    changes => { '*' => {
        previous => 'string?!',
        item => '*?',  # Validated separately
    }},
};
sub event_schema () { return $event_schema }
 # Ad-hoc, doesn't conform to any standardized schema schema.
our $index_schema = {
    changed_at => 'timestamp!',  # When this file specifically was last changed
    items => { '!' => true, '*' => 'string' },
};
sub index_schema () { return $index_schema }

 # Current state, loaded if necessary
my $index;
my %events;
 # Editable.  Changes will be validated then committed in one event.
my %write_items;
my $event;

 # Must wrap this around any access.
my $transaction;
sub READ () { return 1; }  # LOCK_SH
sub WRITE () { return 2; }  # LOCK_EX
sub transaction {
    my ($mode, $proc) = @_;
    @_ == 2 or arity_miss 0+@_, 1;
    $mode eq READ or $mode eq WRITE or die "Invalid transaction mode '$mode' (must be READ or WRITE)";
    if (defined $transaction) {
        $transaction == $mode or die "Cannot nest transactions of different types.";
        return $proc->();
    }
    $transaction = $mode;
     # Start
    mkdirs $datadir;
    open my $LOCK, '>', "$datadir/lock" or croak "Failed to acquire $datadir/lock: $!\n";
    flock $LOCK, $mode or croak "Failed to acquire $datadir/lock: $!\n";
    my @r;
    eval {
         # Generate necessary structure
        mkdirs "$datadir/events";
        if (-e "$datadir/index.json") {
            $index = decode_json slurp "$datadir/index.json";
             # Is this check worth the performance hit?  Profiling needed.
            criticize_die $index, $index_schema, "Internal error: index.json is not valid!";
        }
        else {
            $index = {
                changed_at => '',
                items => {},
            };
        }
        my $event = {
            started_at => timestamp,
            source => { interface => 'unknown' },  # TODO: read %ENV
            request => null,
            response => null,
        };
        for (qw(REMOTE_ADDR REMOTE_PORT HTTP_USER_AGENT HTTP_REFERER HTTP_COOKIE USER SSH_CONNECTION)) {
            if (exists $ENV{$_}) {
                $event->{source}{$_} = $ENV{$_};
            }
        }
         # Do the actual code
        @r = $proc->();
         # Finish event structure
        $event->{id} = timestamp;
        until (!-e "$datadir/events/$event->{id}.json") {
            $event->{id} = timestamp;
        }
        my $event_filename = "$datadir/events/$event->{id}.json";
        open my $EVENT, '>', $event_filename or die "Could not open $event_filename for writing: $!";
        chmod 0440, $EVENT or die "Could not chmod event: $!\n";
        if ($transaction == WRITE) {
            my $changed = 0;
            $event->{changes} = {};  # Mark that it was a write transaction even if there are no changes
            for (keys %write_items) {
                if ($write_items{$_}{path} ne $_) {
                    die "Changing path of item is NYI, sorry.\n";
                }
                my $old_event = exists $index->{items}{$_}
                              ? event($index->{items}{$_})
                              : undef;
                if (process_changes($write_items{$_}, defined $old_event ? $old_event->{changes}{$_}{item} : undef)) {
                    $changed = 1;
                    $event->{changes}{$_} = {
                        previous => defined $old_event ? $old_event->{id} : null,
                        item => $write_items{$_},
                    };
                    $index->{items}{$_} = $event->{id};
                }
            }
            $event->{finished_at} = timestamp;
            if ($changed) {
                $index->{changed_at} = $event->{finished_at};
                criticize_die $index, $index_schema, "Internal error: tried to write invalid index!";
            }
            criticize_die $event, $event_schema, "Internal error: tried to write invalid event!";
             # Commit event
            print $EVENT encode_json($event) or die "Could not write to $event_filename: $!\n";
            close $EVENT or die "Could not close $event_filename: $!\n";
             # Commit index
            if ($changed) {
                splat "$datadir/index.json", encode_json($index);
            }
        }
        else {
             # Just commit event
            $event->{finished_at} = timestamp;
            print $EVENT encode_json($event) or die "Could not write to $event_filename: $!\n";
            close $EVENT or die "Could not close $event_filename: $!\n";
        }
    };
    my $mess = $@;
     # Clear data
    $index = undef;
    %events = ();
    %write_items = ();
    $transaction = undef;
     # Release lock and finish dying if necessary
    flock $LOCK, 8 or $mess .= "Failed to release $datadir/lock: $!\n";
    close $LOCK or $mess .= "Failed to close $datadir/lock: $!\n";
    $mess and die $mess;
     # Annoying contextual return hack
    if (@r == 1) {
        return $r[0];
    }
    else {
        return @r;
    }
};

 # Returns a read-only event with the given id.  Dies if non-existent
sub event {
    my ($id) = @_;
    @_ == 1 or croak arity_miss 0+@_, 1;
    defined $id or croak "ID passed to event() as parameter is undefined.";
    defined $transaction or croak "event() called outside of a transaction.";
    if (!exists $events{$id}) {
        my $event = decode_json slurp "$datadir/events/$id.json";
        criticize_die $event, $event_schema, "Internal error: event $id had invalid data.";
        $events{$id} = $event;
    }
    return $events{$id};
}
 # Returns the event for this item, or undef if not registered
sub item_event {
    my ($path) = @_;
    @_ == 1 or croak arity_miss 0+@_, 1;
    defined $path or croak "Path passed to item_event() as parameter is undefined.";
    defined $transaction or croak "item_event() called outside of a transaction.";
    exists $index->{items}{$path} or return undef;
    my $event = event($index->{items}{$path});
    exists $event->{changes}{$path} or die "Internal error: Event $event->{id} was referred to for item $path, but it didn't contain it.\n";
    return $event;
}
 # Returns previous event *ID* for this event and item
sub item_event_previous {
    my ($path, $id) = @_;
    @_ == 2 or croak arity_miss 0+@_, 1;
    defined $path or croak "Path passed to item_event_previous() as first parameter is undefined.";
    defined $id or croak "ID passed to item_event_previous() as second parameter is undefined.";
    my $event = event($id);
    exists $event->{changes}{$path} or croak "Event and item passed to item_event_previous() don't match.";
    return $event->{changes}{$path}{previous};
}

 # Inside a transaction, returns a readable or read-writable item.
 # Returns undef if the item doesn't exist or is deleted.
sub item : lvalue {
    my ($path) = @_;
    @_ == 1 or croak arity_miss 0+@_, 1;
    defined $path or croak "Path passed to item() as parameter is undefined.";
    if ($transaction == READ) {
        my $event = item_event($path) // return undef;
        return $event->{changes}{$path}{item};
    }
    elsif ($transaction == WRITE) {
        if (!exists $write_items{$path}) {
            my $event = item_event($path);
            if (defined $event) {
                $write_items{$path} = clone($event->{changes}{$path}{item});
            }
            else {
                $write_items{$path} = undef;
            }
        }
        return $write_items{$path};
    }
    else {
        croak "item('$path') called outside of a transaction.";
    }
}

sub all_paths {
    @_ == 0 or croak arity_miss 0+@_, 0;
    defined $transaction or croak "all_names() called outside of a transaction.";
    return keys %{$index->{items}};
}
 # Returns a list of pairs of item names with items (aka a raw hash, not a reference)
sub all_items {
    @_ == 0 or croak arity_miss 0+@_, 0;
    defined $transaction or croak "all_items() called outside of a transaction.";
    return map ($_, item($_)), all_paths;
}

sub validate_everything {
    @_ == 0 or croak arity_miss 0+@_, 0;
    croak "validate_everything is not yet implemented.";
}

1;