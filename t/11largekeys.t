##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 4 }

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

##
# large keys
##
my $key1 = "Now is the time for all good men to come to the aid of their country." x 100;
my $key2 = "The quick brown fox jumped over the lazy, sleeping dog." x 1000;

$db->put($key1, "value1");
$db->put($key2, "value2");

ok(
	($db->get($key1) eq "value1") && 
	($db->get($key2) eq "value2")
);

my $test_key = $db->first_key();
ok(
	($test_key eq $key1) || 
	($test_key eq $key2)
);

$test_key = $db->next_key($test_key);
ok(
	($test_key eq $key1) || 
	($test_key eq $key2)
);

$test_key = $db->next_key($test_key);
ok( !$test_key );

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
