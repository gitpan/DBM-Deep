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

unlink "test2.db";
my $db2 = new DBM::Deep "test2.db";
if ($db2->error()) {
	die "ERROR: " . $db2->error();
}

##
# Create structure in $db
##
$db->import(
	hash1 => {
		subkey1 => "subvalue1",
		subkey2 => "subvalue2"
	}
);

##
# Cross-ref nested hash accross DB objects
##
$db2->{hash1} = $db->{hash1};

##
# close, delete $db
##
undef $db;
unlink "test.db";

##
# Make sure $db2 has copy of $db's hash structure
##
ok(
	($db2->{hash1} &&
		($db2->{hash1}->{subkey1} eq "subvalue1") && 
		($db2->{hash1}->{subkey2} eq "subvalue2")
	)
);

##
# close, delete $db2, exit
##
undef $db2;
unlink "test2.db";

exit(0);
