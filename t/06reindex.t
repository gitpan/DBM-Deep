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
	die "ERROR: " . $db->error();
}

##
# put/get many keys
##
my $max_keys = 3000;

for (my $k=0; $k<$max_keys; $k++) {
	$db->put( "hello" . $k, "there" . ($k * 2) );
}

my $count = 0;

for (my $k=0; $k<$max_keys; $k++) {
	if ($db->get("hello" . $k) eq "there" . ($k * 2)) { $count++; }
}

ok( $count == $max_keys );

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
