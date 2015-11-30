#!/usr/bin/perl
use strict;
use warnings;
no warnings 'once';
use Test::More;
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
is_deeply [palace::criticize($item)], [], 'various properties are valid';
$item->{nothing} = 'foo';
is_deeply [palace::criticize($item)], ['Unallowed property nothing at TOP'], 'criticize rejects unallowed properties';
delete $item->{nothing};
delete $item->{name};
is_deeply [palace::criticize($item)], ['Missing required property name at TOP'], 'criticize requires required properties';
my $index = {
};

done_testing;
