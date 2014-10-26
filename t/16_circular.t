##
# DBM::Deep Test
##
use strict;
use Test::More tests => 13;

use_ok( 'DBM::Deep' );

unlink "t/test.db";
my $db = DBM::Deep->new( "t/test.db" );
if ($db->error()) {
	die "ERROR: " . $db->error();
}

##
# put/get simple keys
##
$db->{key1} = "value1";
$db->{key2} = "value2";

##
# Insert circular reference
##
$db->{circle} = $db;

##
# Make sure keys exist in both places
##
is( $db->{key1}, 'value1', "The value is there directly" );
is( $db->{circle}{key1}, 'value1', "The value is there in one loop of the circle" );
is( $db->{circle}{circle}{key1}, 'value1', "The value is there in two loops of the circle" );
is( $db->{circle}{circle}{circle}{key1}, 'value1', "The value is there in three loops of the circle" );

##
# Make sure changes are reflected in both places
##
$db->{key1} = "another value";

is( $db->{key1}, 'another value', "The value is there directly" );
is( $db->{circle}{key1}, 'another value', "The value is there in one loop of the circle" );
is( $db->{circle}{circle}{key1}, 'another value', "The value is there in two loops of the circle" );
is( $db->{circle}{circle}{circle}{key1}, 'another value', "The value is there in three loops of the circle" );

$db->{circle}{circle}{circle}{circle}{key1} = "circles";

is( $db->{key1}, 'circles', "The value is there directly" );
is( $db->{circle}{key1}, 'circles', "The value is there in one loop of the circle" );
is( $db->{circle}{circle}{key1}, 'circles', "The value is there in two loops of the circle" );
is( $db->{circle}{circle}{circle}{key1}, 'circles', "The value is there in three loops of the circle" );
