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
my $db = new DBM::Deep(
	file => "test.db",
	autoflush => 1
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}
$db->{key1} = "value1";
$db->{key2} = "value2";
my $before = (stat($db->fh()))[7];
undef $db;

##
# set pack to 2-byte (16-bit) words
##
DBM::Deep::set_pack(2, 'S');

unlink "test.db";
$db = new DBM::Deep(
	file => "test.db",
	autoflush => 1
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}
$db->{key1} = "value1";
$db->{key2} = "value2";
my $after = (stat($db->fh()))[7];
undef $db;

ok( $after < $before );

##
# close, delete file, exit
##
# undef $db;
unlink "test.db";
exit(0);
