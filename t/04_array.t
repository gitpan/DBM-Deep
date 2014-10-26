##
# DBM::Deep Test
##
use strict;
use Test::More tests => 99;
use Test::Exception;

use_ok( 'DBM::Deep' );

##
# basic file open
##
unlink "t/test.db";
my $db = DBM::Deep->new(
	file => "t/test.db",
	type => DBM::Deep->TYPE_ARRAY
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

TODO: {
    local $TODO = "How is this test ever supposed to pass?";
    ok( !$db->clear, "If the file has never been written to, clear() returns false" );
}

##
# basic put/get/push
##
$db->[0] = "elem1";
$db->push( "elem2" );
$db->put(2, "elem3");
$db->store(3, "elem4");
$db->unshift("elem0");

is( $db->[0], 'elem0', "Array get for shift works" );
is( $db->[1], 'elem1', "Array get for array set works" );
is( $db->[2], 'elem2', "Array get for push() works" );
is( $db->[3], 'elem3', "Array get for put() works" );
is( $db->[4], 'elem4', "Array get for store() works" );

is( $db->get(0), 'elem0', "get() for shift() works" );
is( $db->get(1), 'elem1', "get() for array set works" );
is( $db->get(2), 'elem2', "get() for push() works" );
is( $db->get(3), 'elem3', "get() for put() works" );
is( $db->get(4), 'elem4', "get() for store() works" );

is( $db->fetch(0), 'elem0', "fetch() for shift() works" );
is( $db->fetch(1), 'elem1', "fetch() for array set works" );
is( $db->fetch(2), 'elem2', "fetch() for push() works" );
is( $db->fetch(3), 'elem3', "fetch() for put() works" );
is( $db->fetch(4), 'elem4', "fetch() for store() works" );

is( $db->length, 5, "... and we have five elements" );

is( $db->[-1], $db->[4], "-1st index is 4th index" );
is( $db->[-2], $db->[3], "-2nd index is 3rd index" );
is( $db->[-3], $db->[2], "-3rd index is 2nd index" );
is( $db->[-4], $db->[1], "-4th index is 1st index" );
is( $db->[-5], $db->[0], "-5th index is 0th index" );
is( $db->[-6], undef, "-6th index is undef" );
is( $db->length, 5, "... and we have five elements after abortive -6 index lookup" );

$db->[-1] = 'elem4.1';
is( $db->[-1], 'elem4.1' );
is( $db->[4], 'elem4.1' );
is( $db->get(4), 'elem4.1' );
is( $db->fetch(4), 'elem4.1' );

throws_ok {
    $db->[-6] = 'whoops!';
} qr/Modification of non-creatable array value attempted, subscript -6/, "Correct error thrown"; 

my $popped = $db->pop;
is( $db->length, 4, "... and we have four after popping" );
is( $db->[0], 'elem0', "0th element still there after popping" );
is( $db->[1], 'elem1', "1st element still there after popping" );
is( $db->[2], 'elem2', "2nd element still there after popping" );
is( $db->[3], 'elem3', "3rd element still there after popping" );
is( $popped, 'elem4.1', "Popped value is correct" );

my $shifted = $db->shift;
is( $db->length, 3, "... and we have three after shifting" );
is( $db->[0], 'elem1', "0th element still there after shifting" );
is( $db->[1], 'elem2', "1st element still there after shifting" );
is( $db->[2], 'elem3', "2nd element still there after shifting" );
is( $shifted, 'elem0', "Shifted value is correct" );

##
# delete
##
my $deleted = $db->delete(0);
is( $db->length, 3, "... and we still have three after deleting" );
is( $db->[0], undef, "0th element now undef" );
is( $db->[1], 'elem2', "1st element still there after deleting" );
is( $db->[2], 'elem3', "2nd element still there after deleting" );
is( $deleted, 'elem1', "Deleted value is correct" );

is( $db->delete(99), undef, 'delete on an element not in the array returns undef' );
is( $db->length, 3, "... and we still have three after a delete on an out-of-range index" );

is( delete $db->[99], undef, 'DELETE on an element not in the array returns undef' );
is( $db->length, 3, "... and we still have three after a DELETE on an out-of-range index" );

is( $db->delete(-99), undef, 'delete on an element (neg) not in the array returns undef' );
is( $db->length, 3, "... and we still have three after a DELETE on an out-of-range negative index" );

is( delete $db->[-99], undef, 'DELETE on an element (neg) not in the array returns undef' );
is( $db->length, 3, "... and we still have three after a DELETE on an out-of-range negative index" );

$deleted = $db->delete(-2);
is( $db->length, 3, "... and we still have three after deleting" );
is( $db->[0], undef, "0th element still undef" );
is( $db->[1], undef, "1st element now undef" );
is( $db->[2], 'elem3', "2nd element still there after deleting" );
is( $deleted, 'elem2', "Deleted value is correct" );

$db->[1] = 'elem2';

##
# exists
##
ok( $db->exists(1), "The 1st value exists" );
ok( !$db->exists(0), "The 0th value doesn't exists" );
ok( !$db->exists(22), "The 22nd value doesn't exists" );
ok( $db->exists(-1), "The -1st value does exists" );
ok( !$db->exists(-22), "The -22nd value doesn't exists" );

##
# clear
##
ok( $db->clear(), "clear() returns true if the file was ever non-empty" );
is( $db->length(), 0, "After clear(), no more elements" );

is( $db->pop, undef, "pop on an empty array returns undef" );
is( $db->length(), 0, "After pop() on empty array, length is still 0" );

is( $db->shift, undef, "shift on an empty array returns undef" );
is( $db->length(), 0, "After shift() on empty array, length is still 0" );

is( $db->unshift( 1, 2, 3 ), 3, "unshift returns the number of elements in the array" );
is( $db->unshift( 1, 2, 3 ), 6, "unshift returns the number of elements in the array" );
is( $db->push( 1, 2, 3 ), 9, "push returns the number of elements in the array" );

is( $db->length(), 9, "After unshift and push on empty array, length is now 9" );

$db->clear;

##
# multi-push
##
$db->push( 'elem first', "elem middle", "elem last" );
is( $db->length, 3, "3-element push results in three elements" );
is($db->[0], "elem first", "First element is 'elem first'");
is($db->[1], "elem middle", "Second element is 'elem middle'");
is($db->[2], "elem last", "Third element is 'elem last'");

##
# splice with length 1
##
my @returned = $db->splice( 1, 1, "middle A", "middle B" );
is( scalar(@returned), 1, "One element was removed" );
is( $returned[0], 'elem middle', "... and it was correctly removed" );
is($db->length(), 4);
is($db->[0], "elem first");
is($db->[1], "middle A");
is($db->[2], "middle B");
is($db->[3], "elem last");

##
# splice with length of 0
##
@returned = $db->splice( -1, 0, "middle C" );
is( scalar(@returned), 0, "No elements were removed" );
is($db->length(), 5);
is($db->[0], "elem first");
is($db->[1], "middle A");
is($db->[2], "middle B");
is($db->[3], "middle C");
is($db->[4], "elem last");

##
# splice with length of 3
##
my $returned = $db->splice( 1, 3, "middle ABC" );
is( $returned, 'middle C', "Just the last element was returned" );
is($db->length(), 3);
is($db->[0], "elem first");
is($db->[1], "middle ABC");
is($db->[2], "elem last");

# These tests verify that the hash methods cannot be called on arraytypes.
# They will be removed once the ARRAY and HASH types are refactored into their own classes.

$db->[0] = [ 1 .. 3 ];
$db->[1] = { a => 'foo' };
is( $db->[0]->length, 3, "Reuse of same space with array successful" );
is( $db->[1]->fetch('a'), 'foo', "Reuse of same space with hash successful" );
