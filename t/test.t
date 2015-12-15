#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Test::More;
use File::Path;
use JSON::MaybeXS ':all';
use lib '.';
use backend::filesystem ':all';

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

$backend::filesystem::datadir = 't/test-data';
$backend::filesystem::test_time = 0;
$ENV{USER} = 'foo';
delete $ENV{SSH_CONNECTION};

note 'Datetimes';
is now(), 0, 'now seems to work';
is_deeply [now_hires()], [1, 123456], 'now_hires seems to work';
is timestamp(now()), '1970-01-01_00-00-02', 'timestamp(now()) seems to work';
is timestamp(now_hires()), '1970-01-01_00-00-03_123456', 'timestamp(now()) seems to work';
is timestamp(), '1970-01-01_00-00-04_123456', 'timestamp() seems to work';

note 'Criticize';
my $item = {
    path => 'whatever',
    title => 'The Great Whatever',
    links => [{
        rel => 'next',
        path => 'whatever2',
    },{
        rel => 'tag',
        path => 'tag/whatever',
    },{
        rel => 'credit',
        credit => 0,
        path => 'user/foo',
    }],
    contents => [{
        rel => 'description',
        text => 'this is a thing',
    },{
        rel => 'whatever',
        html => '<b>groovy!</b>',
        origin => 'http://example.com/groovy',
    }],
    credits => [{
        name => 'Tester',
        uri => 'http://example.com',
        email => 'example@example.com',
    }],
    uploader => 0,
    access => { public => true, visible => true },
    auto => {
        created_at => '1970-01-01_00-00-00_123456',
        changed_at => '1970-01-01_00-00-00_123456',
        linked => ['thing1', 'thing2'],
    },
    misc => {
        anything => 'goes',
        extra => [qw(a b c d e)],
    },
};
is_deeply [criticize($item, item_schema)], [], 'various properties are valid';
$item->{nothing} = 'foo';
is_deeply [criticize($item, item_schema)], ['Unallowed property nothing at TOP'], 'criticize rejects unallowed properties';
delete $item->{nothing};
delete $item->{path};
is_deeply [criticize($item, item_schema)], ['Missing required property path at TOP'], 'criticize requires required properties';
$item->{path} = 'foo';
$item->{uploader} = 1;
is_deeply [criticize($item, item_schema)], ['Value at TOP.uploader is out of range for credits array'], 'criticize uses embedded criticism function';
$item->{uploader} = 0;
my $index = {
    changed_at => '1970-01-01_00-00-00_123456',
    items => {
        foo => '1970-01-01_00-00-00_435789',
        bar => '2134-11-21_21-52-10_010002',
    },
};
is_deeply [criticize($index, index_schema)], [], 'valid index passes criticism';
my $event = {
    id => '1970-01-01_00-00-00_435789',
    started_at => '1970-01-01_00-00-00_123456',
    finished_at => '1970-01-01_00-00-00_123456',
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
is_deeply [criticize($event, event_schema)], [], 'valid event passes criticism';


note 'Backend internal';
my $res;
lives sub { $res = backend::filesystem::process_changes($item, undef); }, 'process_changes lives with item and null';
ok $res, 'process_changes returned true with item and null';
is $item->{auto}{changed_at}, '1970-01-01_00-00-05_123456', 'process_changes set changed_at';
is $item->{auto}{created_at}, '1970-01-01_00-00-05_123456', 'process_changes set created_at';

note 'Backend';
File::Path::remove_tree("t/test-data");
lives sub {
    transaction(READ, sub {});
}, 'empty READ transaction lives';
is_deeply [glob('t/test-data/events/*')],
          ['t/test-data/events/1970-01-01_00-00-07_123456.json'],
          'READ transaction wrote an event file';
my $read_event = {
    id => '1970-01-01_00-00-07_123456',
    source => { interface => 'unknown', USER => 'foo' },
    request => undef,
    response => undef,
    started_at => '1970-01-01_00-00-06_123456',
    finished_at => '1970-01-01_00-00-08_123456',
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
    path => 'foo',
    auto => {
        linked => [],
        created_at => '1970-01-01_00-00-11_123456',
        changed_at => '1970-01-01_00-00-11_123456',
    },
};
my $write_event = {
    id => '1970-01-01_00-00-10_123456',
    source => { interface => 'unknown', USER => 'foo' },
    request => undef,
    response => undef,
    started_at => '1970-01-01_00-00-09_123456',
    finished_at => '1970-01-01_00-00-12_123456',
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
    changed_at => '1970-01-01_00-00-12_123456',
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
