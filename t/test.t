#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Test::More;
use File::Path;
require 'palace';

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
is palace::now(), 0, 'now seems to work';
is_deeply [palace::now_hires()], [1, 123456], 'now_hires seems to work';
is palace::iso_datetime(gmtime(palace::now())), '1970-01-01T00:00:02Z', 'iso_datetime seems to work';
is palace::file_datetime(gmtime(palace::now())), '1970-01-01_00-00-03', 'file_datetime seems to work';
is palace::new_event_id(), '1970-01-01_00-00-04_123456', 'new_event_id seems to work';

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
is_deeply [palace::criticize($item, $palace::item_schema)], [], 'various properties are valid';
$item->{nothing} = 'foo';
is_deeply [palace::criticize($item, $palace::item_schema)], ['Unallowed property nothing at TOP'], 'criticize rejects unallowed properties';
delete $item->{nothing};
delete $item->{name};
is_deeply [palace::criticize($item, $palace::item_schema)], ['Missing required property name at TOP'], 'criticize requires required properties';
$item->{name} = 'foo';
my $index = {
    changed_at => '1970-01-01T00:00:00Z',
    items => {
        foo => '1970-01-01_00-00-00_435789',
        bar => '2134-11-21_21-52-10_010002',
    },
};
is_deeply [palace::criticize($index, $palace::index_schema)], [], 'valid index passes criticism';
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
is_deeply [palace::criticize($event, $palace::event_schema)], [], 'valid event passes criticism';


note 'Backend';
File::Path::remove_tree("t/test-data");
my $res;
lives sub { $res = palace::process_changes($item, undef); }, 'process_changes lives with item and null';
ok $res, 'process_changes returned true with item and null';
is $item->{auto}{changed_at}, '1970-01-01T00:00:05Z', 'process_changes set changed_at';
is $item->{auto}{created_at}, '1970-01-01T00:00:05Z', 'process_changes set created_at';

done_testing;
