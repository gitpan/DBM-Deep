##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 3 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep "test.db";
if ($db->error()) {
	die "ERROR: " . $db->error();
}

ok( !$db->error() );

##
# cause an error
##
$db->push("foo"); # ERROR -- array-only method

ok( $db->error() );

$db->clear_error();

ok( !$db->error() );

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
