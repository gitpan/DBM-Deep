##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 2 }

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
ok(
	($db->{key1} eq "value1") && 
	($db->{circle}->{key1} eq "value1")
);

##
# Make sure changes are reflected in both places
##
$db->{key1} = "another value";

ok(
	($db->{key1} eq "another value") && 
	($db->{circle}->{key1} eq "another value")
);

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
