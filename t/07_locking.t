##
# DBM::Deep Test
##
use strict;
use Test::More tests => 5;
use Test::Exception;
use t::common qw( new_fh );

use_ok( 'DBM::Deep' );

my ($fh, $filename) = new_fh();
my $db = DBM::Deep->new(
	file => $filename,
	locking => 1,
);

lives_ok {
    $db->unlock;
} "Can call unlock on an unlocked DB.";

##
# basic put/get
##
$db->{key1} = "value1";
is( $db->{key1}, "value1", "key1 is set" );

$db->{key2} = [ 1 .. 3 ];
is( $db->{key2}[1], 2 );

##
# explicit lock
##
$db->lock( DBM::Deep->LOCK_EX );
$db->{key1} = "value2";
$db->unlock();
is( $db->{key1}, "value2", "key1 is overridden" );
