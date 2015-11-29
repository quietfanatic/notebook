#!/usr/bin/perl
use strict;
use warnings;
use Test::More;
require 'palace';

diag 'Name mangling';
is palace::encode_name('asdf%\'"/foo'), 'asdf%25%27%22%2Ffoo', 'encode_name';
is palace::decode_name('asdf%25%27%22%2Ffoo'), 'asdf%\'"/foo', 'decode_name';

diag 'Criticize';
is_deeply [palace::criticize({name => 'foo'})], [], '{name => \'foo\'} is valid';
is_deeply [palace::criticize({})], ['Missing required property name at TOP'], 'name is required property';
is_deeply [palace::criticize({name => 'foo', nope => 'foo'})], ['Unallowed property nope at TOP'], 'check for unallowed property';
my $object = {
    name => 'whatever',
    uri => 'http://example.com/whatever',
    added => '1970-01-01T00:00:00Z',
    updated => '1970-01-01T00:00:00Z',
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
