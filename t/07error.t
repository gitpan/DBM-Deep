##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 2 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep "test.db";

##
# cause an error
##
eval { $db->push("foo"); }; # ERROR -- array-only method

ok( $db->error() );

$db->clear_error();

ok( !$db->error() );

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
