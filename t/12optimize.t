##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 3 }

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

##
# create some unused space
##
$db->{key1} = "value1";
$db->{key2} = "value2";

$db->{a} = {};
$db->{a}->{b} = [];

my $b = $db->{a}->{b};
$b->[0] = 1;
$b->[1] = 2;
$b->[2] = {};
$b->[2]->{c} = [];

my $c = $b->[2]->{c};
$c->[0] = 'd';
$c->[1] = {};
$c->[1]->{e} = 'f';

undef $c;
undef $b;

delete $db->{a};

##
# take byte count readings before, and after optimize
##
my $before = (stat($db->fh()))[7];
my $result = $db->optimize();
my $after = (stat($db->fh()))[7];

if ($db->error()) {
	die "ERROR: " . $db->error();
}

ok( $result );
ok( $after < $before ); # make sure file shrunk

ok(
	($db->{key1} eq "value1") && 
	($db->{key2} eq "value2")
); # make sure content is still there

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
