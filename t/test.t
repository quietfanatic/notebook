#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
require 'palace';

is_deeply [palace::criticize({name => 'foo'})], [], '{name => \'foo\'} is valid';
is_deeply [palace::criticize({})], ['Missing required property name at TOP'], 'name is required property';
is_deeply [palace::criticize({name => 'foo', nope => 'foo'})], ['Unallowed property nope at TOP'], 'check for unallowed property';
my $object = {
    name => 'whatever',
    url => 'http://example.com/whatever',
    added => '1970-01-01T00:00:00',
    updated => '1970-01-01T00:00:00',
    tags => ['a', 'b'],
    tagged => ['thing1', 'thing2'],
    comments => ['this is a thing', 'haha I\'m typing words'],
    misc => {
        anything => 'goes',
        extra => [qw(a b c d e)],
    },
};
is_deeply [palace::criticize($object)], [], 'various properties are valid';

done_testing;
