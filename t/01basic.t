##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 1 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep "test.db";
if ($db->error()) {
	print "ERROR: " . $db->error();
	ok(0);
	exit(0);
}
else { ok(1); }
