##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 11 }

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
# basic put/get/push
##
$db->[0] = "elem0";
push @$db, "elem1";
$db->put(2, "elem2");

ok(
	($db->[0] eq "elem0") && 
	($db->[1] eq "elem1") && 
	($db->[2] eq "elem2")
);

ok(
	($db->get(0) eq "elem0") && 
	($db->get(1) eq "elem1") && 
	($db->get(2) eq "elem2")
);

##
# pop, shift
##
my $popped = pop @$db;
ok(
	($db->length() == 2) && 
	($db->[0] eq "elem0") && 
	($db->[1] eq "elem1") && 
	($popped eq "elem2")
);

my $shifted = shift @$db;
ok(
	($db->length() == 1) && 
	($db->[0] eq "elem1") && 
	($shifted eq "elem0")
);

##
# unshift
##
$db->unshift( "new elem" );
ok(
	($db->length() == 2) && 
	($db->[0] eq "new elem") && 
	($db->[1] eq "elem1")
);

##
# delete
##
$db->delete(0);
ok(
	($db->length() == 2) && 
	(!$db->[0]) && 
	($db->[1] eq "elem1")
);

##
# exists
##
ok( $db->exists(1) );

##
# clear
##
$db->clear();
ok( $db->length() == 0 );

##
# multi-push
##
$db->push( "elem first", "elem middle", "elem last" );
ok(
	($db->length() == 3) && 
	($db->[0] eq "elem first") && 
	($db->[1] eq "elem middle") && 
	($db->[2] eq "elem last")
);

##
# splice
##
$db->splice( 1, 1, "middle A", "middle B" );
ok(
	($db->length() == 4) && 
	($db->[0] eq "elem first") && 
	($db->[1] eq "middle A") && 
	($db->[2] eq "middle B") && 
	($db->[3] eq "elem last")
);

##
# splice with length of 0
##
$db->splice( 3, 0, "middle C" );
ok(
	($db->length() == 5) && 
	($db->[0] eq "elem first") && 
	($db->[1] eq "middle A") && 
	($db->[2] eq "middle B") && 
	($db->[3] eq "middle C") && 
	($db->[4] eq "elem last")
);

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
