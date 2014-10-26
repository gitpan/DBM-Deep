##
# DBM::Deep Test
##
$|++;
use strict;
use Test::More;

my $max_levels = 1000;

plan tests => 3;

use_ok( 'DBM::Deep' );

unlink "t/test.db";
my $db = DBM::Deep->new(
	file => "t/test.db",
	type => DBM::Deep->TYPE_ARRAY,
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

$db->[0] = [];
my $temp_db = $db->[0];
for my $k ( 0 .. $max_levels ) {
	$temp_db->[$k] = [];
	$temp_db = $temp_db->[$k];
}
$temp_db->[0] = "deepvalue";
undef $temp_db;

undef $db;
$db = DBM::Deep->new(
	file => "t/test.db",
	type => DBM::Deep->TYPE_ARRAY,
);

my $cur_level = -1;
$temp_db = $db->[0];
for my $k ( 0 .. $max_levels ) {
    $cur_level = $k;
    $temp_db = $temp_db->[$k];
    eval { $temp_db->isa( 'DBM::Deep' ) } or last;
}
is( $cur_level, $max_levels, "We read all the way down to level $cur_level" );
is( $temp_db->[0], "deepvalue", "And we retrieved the value at the bottom of the ocean" );
