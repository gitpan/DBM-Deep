##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 15 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep "test.db";
if ($db->error()) {
	die "ERROR: " . $db->error();
}

##
# put/get key
##
$db->{key1} = "value1";
ok( $db->{key1} eq "value1" );

$db->put("key2", "value2");
ok( $db->get("key2") eq "value2" );

##
# key exists
##
ok( $db->exists("key1") );
ok( exists $db->{key2} );

##
# count keys
##
ok( scalar keys %$db == 2 );

##
# step through keys
##
my $temphash = {};
while ( my ($key, $value) = each %$db ) {
	$temphash->{$key} = $value;
}

ok( ($temphash->{key1} eq "value1") && ($temphash->{key2} eq "value2") );

$temphash = {};
my $key = $db->first_key();
while ($key) {
	$temphash->{$key} = $db->get($key);
	$key = $db->next_key($key);
}

ok( ($temphash->{key1} eq "value1") && ($temphash->{key2} eq "value2") );

##
# delete keys
##
ok( delete $db->{key1} );
ok( $db->delete("key2") );

ok( scalar keys %$db == 0 );

##
# delete all keys
##
$db->put("another", "value");
$db->clear();

ok( scalar keys %$db == 0 );

##
# replace key
##
$db->put("key1", "value1");
$db->put("key1", "value2");

ok( $db->get("key1") eq "value2" );

$db->put("key1", "value222222222222222222222222");

ok( $db->get("key1") eq "value222222222222222222222222" );

##
# Make sure DB still works after closing / opening
##
undef $db;
$db = new DBM::Deep "test.db";
if ($db->error()) {
	die "ERROR: " . $db->error();
}
ok( $db->get("key1") eq "value222222222222222222222222" );

##
# Make sure keys are still fetchable after replacing values
# with smaller ones (bug found by John Cardenas, DBM::Deep 0.93)
##
$db->clear();
$db->put("key1", "long value here");
$db->put("key2", "longer value here");

$db->put("key1", "short value");
$db->put("key2", "shorter v");

my $first_key = $db->first_key();
my $next_key = $db->next_key($first_key);

ok(
	(($first_key eq "key1") || ($first_key eq "key2")) && 
	(($next_key eq "key1") || ($next_key eq "key2")) && 
	($first_key ne $next_key)
);

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
