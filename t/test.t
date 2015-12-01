#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Test::More;
use File::Path;
use JSON::MaybeXS ':all';
BEGIN {
    require 'palace';
    palace->import(':all');
}

sub lives {
    eval { $_[0]() };
    is $@, '', $_[1];
}
sub dies {
    eval { $_[0]() };
    if ($@) {
        pass $_[1];
    }
    else {
        fail $_[1];
    }
}

$palace::datadir = 't/test-data';
$palace::test_time = 0;

note 'Datetimes';
is now(), 0, 'now seems to work';
is_deeply [now_hires()], [1, 123456], 'now_hires seems to work';
is iso_datetime(gmtime(now())), '1970-01-01T00:00:02Z', 'iso_datetime seems to work';
is file_datetime(gmtime(now())), '1970-01-01_00-00-03', 'file_datetime seems to work';
is new_event_id(), '1970-01-01_00-00-04_123456', 'new_event_id seems to work';

note 'Criticize';
my $item = {
    name => 'whatever',
    origin => {
        uri => 'http://example.com/whatever',
    },
    tags => ['a', 'b'],
    contents => ['this is a thing', 'haha I\'m typing words'],
    auto => {
        created_at => '1970-01-01T00:00:00Z',
        changed_at => '1970-01-01T00:00:00Z',
        tagged => ['thing1', 'thing2'],
    },
    misc => {
        anything => 'goes',
        extra => [qw(a b c d e)],
    },
};
is_deeply [criticize($item, $palace::item_schema)], [], 'various properties are valid';
$item->{nothing} = 'foo';
is_deeply [criticize($item, $palace::item_schema)], ['Unallowed property nothing at TOP'], 'criticize rejects unallowed properties';
delete $item->{nothing};
delete $item->{name};
is_deeply [criticize($item, $palace::item_schema)], ['Missing required property name at TOP'], 'criticize requires required properties';
$item->{name} = 'foo';
my $index = {
    changed_at => '1970-01-01T00:00:00Z',
    items => {
        foo => '1970-01-01_00-00-00_435789',
        bar => '2134-11-21_21-52-10_010002',
    },
};
is_deeply [criticize($index, $palace::index_schema)], [], 'valid index passes criticism';
my $event = {
    id => '1970-01-01_00-00-00_435789',
    started_at => '1970-01-01T00:00:00Z',
    finished_at => '1970-01-01T00:00:00Z',
    source => {
        interface => 'test',
        foo => 'bar',
    },
    request => 'test',
    response => 'whatever',
    changes => {
        foo => {
            previous => undef,
            item => $item,
        },
        deleted => {
            previous => undef,
            item => undef,
        }
    },
};
is_deeply [criticize($event, $palace::event_schema)], [], 'valid event passes criticism';


note 'Backend internal';
my $res;
lives sub { $res = palace::process_changes($item, undef); }, 'process_changes lives with item and null';
ok $res, 'process_changes returned true with item and null';
is $item->{auto}{changed_at}, '1970-01-01T00:00:05Z', 'process_changes set changed_at';
is $item->{auto}{created_at}, '1970-01-01T00:00:05Z', 'process_changes set created_at';

note 'Backend';
File::Path::remove_tree("t/test-data");
lives sub {
    transaction(palace::READ(), sub {});
}, 'empty READ transaction lives';
is_deeply [glob('t/test-data/events/*')],
          ['t/test-data/events/1970-01-01_00-00-07_123456.json'],
          'READ transaction wrote an event file';
my $read_event = {
    id => '1970-01-01_00-00-07_123456',
    source => { interface => 'unknown' },
    request => undef,
    response => undef,
    started_at => '1970-01-01T00:00:06Z',
    finished_at => '1970-01-01T00:00:08Z',
};
is_deeply decode_json(slurp('t/test-data/events/1970-01-01_00-00-07_123456.json')),
          $read_event,
          'Event written by READ transaction is correct';
lives sub {
    transaction(WRITE, sub {
        item('foo') = blank_item('foo');
    });
}, 'basic WRITE transaction works';
is_deeply [sort(glob('t/test-data/events/*'))],
          ['t/test-data/events/1970-01-01_00-00-07_123456.json', 't/test-data/events/1970-01-01_00-00-10_123456.json'],
          'WRITE transaction wrote an event file';
my $write_item = {
    name => 'foo',
    tags => [],
    contents => [],
    auto => {
        tagged => [],
        created_at => '1970-01-01T00:00:11Z',
        changed_at => '1970-01-01T00:00:11Z',
    },
};
my $write_event = {
    id => '1970-01-01_00-00-10_123456',
    source => { interface => 'unknown' },
    request => undef,
    response => undef,
    started_at => '1970-01-01T00:00:09Z',
    finished_at => '1970-01-01T00:00:12Z',
    changes => {
        foo => {
            previous => undef,
            item => $write_item,
        },
    },
};
is_deeply decode_json(slurp('t/test-data/events/1970-01-01_00-00-10_123456.json')),
          $write_event,
          'Event written by WRITE transaction is correct';
ok -e 't/test-data/index.json', 'WRITE transaction wrote index.json';
is_deeply decode_json(slurp('t/test-data/index.json')), {
    changed_at => '1970-01-01T00:00:12Z',
    items => { foo => '1970-01-01_00-00-10_123456' },
}, 'Index written by WRITE transaction is correct';
my $out;
lives sub {
    transaction(READ, sub {
        $out = item('foo');
    });
}, 'READ transaction can read an item';
is_deeply $out, $write_item, 'READ transaction correctly read item written by WRITE transaction';

done_testing;
