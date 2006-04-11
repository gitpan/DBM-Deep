#!/usr/bin/perl -l

##
# DBM::Deep Test
#
# Test for interference from -l on the commandline.
##
use strict;
use Test::More tests => 4;
use Test::Exception;

use_ok( 'DBM::Deep' );

unlink "t/test.db";
my $db = DBM::Deep->new( 't/test.db' );

##
# put/get key
##
$db->{key1} = "value1";
is( $db->get("key1"), "value1", "get() works with hash assignment" );
is( $db->fetch("key1"), "value1", "... fetch() works with hash assignment" );
is( $db->{key1}, "value1", "... and hash-access also works" );
