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
my $db = new DBM::Deep(
	file => "test.db"
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

$db->{key1} = "value1";

##
# clone db handle, make sure both are usable
##
my $clone = $db->clone();
$clone->{key2} = "value2";

ok(
	($db->{key1} eq "value1") && 
	($db->{key2} eq "value2")
);

ok(
	($clone->{key1} eq "value1") && 
	($clone->{key2} eq "value2")
);

undef $clone;

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
