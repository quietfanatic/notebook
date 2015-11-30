#!/usr/bin/perl
use strict;
use warnings;
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
mkdir 't/test-data';
mkdir 't/test-data/things';

note 'Criticize';
my $object = {
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
is_deeply [palace::criticize($object)], [], 'various properties are valid';
$object->{nothing} = 'foo';
is_deeply [palace::criticize($object)], ['Unallowed property nothing at TOP'], 'criticize rejects unallowed properties';
delete $object->{nothing};
delete $object->{name};
is_deeply [palace::criticize($object)], ['Missing required property name at TOP'], 'criticize requires required properties';

=cut
note 'Backend';
unlink palace::name_file('foo');
unlink palace::name_file('bar');
unlink palace::name_file('newfoo');

my $in = {name => 'foo'};
lives sub { palace::write_item($in) }, 'can use write_item';
my $out;
lives sub { $out = palace::read_item('foo') }, 'can use read_item';
is_deeply $out, $in, 'write_item and read_item roundtrip';

lives sub { palace::write_item({name => 'bar'}) }, 'write_item again';
lives sub { palace::update_item('bar', sub { my $i = $_[0]; $i->{misc} = {}; return $i; }) }, 'can use update_item';
is_deeply palace::read_item('bar'), {name => 'bar', misc => {}}, 'update_item worked correctly';

is_deeply [sort { $a cmp $b } palace::all_names()], ['bar', 'foo'], 'all_names works';
lives sub { $out = palace::all_items() }, 'all_items lives';
is_deeply $out, {foo => {name => 'foo'}, bar => {name => 'bar', misc => {}}}, 'all_items works';

is_deeply [palace::validate_everything()], [], 'test data is valid';

lives sub { palace::delete_item('foo') }, 'can use delete_item';
ok !-e palace::name_file('foo'), 'delete_item did delete the item\'s file';

dies sub { palace::write_item({name => 'bad', bad => undef}) }, 'write_item requires valid data';
dies sub { palace::update_item('bar', sub{ return {name => 'bar', bad => undef} }) }, 'update_item requires valid data';

note 'raw frontend';
$in = '{"name":"newfoo"}';
lives sub { palace::raw_add($in) }, 'can use raw_add';
lives sub { $out = palace::raw_show('newfoo') }, 'can use raw_show';
is $out, $in, 'raw_add and raw_show roundtrip';
dies sub { palace::raw_add($in) }, 'cannot raw_add if it already exists';
=cut
done_testing;
