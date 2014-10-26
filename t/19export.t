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
# Create structure in DB
##
$db->import(
	key1 => "value1",
	key2 => "value2",
	array1 => [ "elem0", "elem1", "elem2" ],
	hash1 => {
		subkey1 => "subvalue1",
		subkey2 => "subvalue2"
	}
);

##
# Export entire thing
##
my $struct = $db->export();

##
# close, delete file
##
undef $db;
unlink "test.db";

##
# Make sure everything is here, outside DB
##
ok(
	($struct->{key1} eq "value1") && 
	($struct->{key2} eq "value2") && 
	($struct->{array1} && 
		($struct->{array1}->[0] eq "elem0") &&
		($struct->{array1}->[1] eq "elem1") && 
		($struct->{array1}->[2] eq "elem2")
	) && 
	($struct->{hash1} &&
		($struct->{hash1}->{subkey1} eq "subvalue1") && 
		($struct->{hash1}->{subkey2} eq "subvalue2")
	)
);

exit(0);
