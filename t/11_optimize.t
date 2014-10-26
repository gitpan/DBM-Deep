##
# DBM::Deep Test
##
use strict;
use Test::More tests => 9;

use_ok( 'DBM::Deep' );

unlink "t/test.db";
my $db = DBM::Deep->new(
	file => "t/test.db",
	autoflush => 1,
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
$db->{a}{b} = [];
$db->{a}{c} = 'value2';

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

delete $db->{key2};
delete $db->{a}{b};

##
# take byte count readings before, and after optimize
##
my $before = (stat($db->fh()))[7];
my $result = $db->optimize();
my $after = (stat($db->fh()))[7];

if ($db->error()) {
	die "ERROR: " . $db->error();
}

ok( $result, "optimize succeeded" );
ok( $after < $before, "file size has shrunk" ); # make sure file shrunk

is( $db->{key1}, 'value1', "key1's value is still there after optimize" );
is( $db->{a}{c}, 'value2', "key2's value is still there after optimize" );

##
# now for the tricky one -- try to store a new key while file is being
# optimized and locked by another process.  filehandle should be invalidated, 
# and automatically re-opened transparently.  Cannot test on Win32, due to 
# problems with fork()ing, flock()ing, etc.  Win32 very bad.
##

SKIP: {
    skip "Fork tests skipped on Win32", 4 if $^O eq 'MSWin32';

    ##
    # first things first, get us about 1000 keys so the optimize() will take 
    # at least a few seconds on any machine, and re-open db with locking
    ##
    for (1..1000) { $db->STORE( $_, $_ ); }
    undef $db;

    ##
    # now, fork a process for the optimize()
    ##
    my $pid = fork();

    unless ( $pid ) {
        # child fork
        
        # re-open db
        $db = DBM::Deep->new(
            file => "t/test.db",
            autoflush => 1,
            locking => 1
        );
        if ($db->error()) {
            die "ERROR: " . $db->error();
        }
        
        # optimize and exit
        $db->optimize();

        exit( 0 );
    }

    # parent fork
    ok( defined($pid), "fork was successful" ); # make sure fork was successful
    
    # re-open db
    $db = DBM::Deep->new(
        file => "t/test.db",
        autoflush => 1,
        locking => 1
    );
    if ($db->error()) {
        die "ERROR: " . $db->error();
    }
    
    # sleep for 1 second to make sure optimize() is running in the other fork
    sleep(1);
    
    # now, try to get a lock and store a key
    $db->{parentfork} = "hello";
    
    # see if it was stored successfully
    is( $db->{parentfork}, "hello", "stored key while optimize took place" );
    # ok(1);
    
    # now check some existing values from before
    is( $db->{key1}, 'value1', "key1's value is still there after optimize" );
    is( $db->{a}{c}, 'value2', "key2's value is still there after optimize" );
}
