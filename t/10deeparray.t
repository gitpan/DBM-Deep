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
	type => DBM::Deep::TYPE_ARRAY
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

##
# super deep array
##
my $max_levels = 500;
$db->[0] = [];
my $temp_db = $db->[0];

for (my $k=0; $k<$max_levels; $k++) {
	$temp_db->[$k] = [];
	$temp_db = $temp_db->[$k];
}
$temp_db->[0] = "deepvalue";
undef $temp_db;

##
# start over, now validate all levels
##
$temp_db = $db->[0];
for (my $k=0; $k<$max_levels; $k++) {
	if ($temp_db) { $temp_db = $temp_db->[$k]; }
}
ok( $temp_db && ($temp_db->[0] eq "deepvalue") );

undef $temp_db;

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
