##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 4 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep(
	file => "test.db"
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

##
# First try store filters only (values will be unfiltered)
##
$db->set_filter( 'store_key', \&my_filter_store_key );
$db->set_filter( 'store_value', \&my_filter_store_value );

$db->{key1} = "value1";
$db->{key2} = "value2";

ok(
	($db->{key1} eq "MYFILTERvalue1") && 
	($db->{key2} eq "MYFILTERvalue2")
);

##
# Now try fetch filters as well
##
$db->set_filter( 'fetch_key', \&my_filter_fetch_key );
$db->set_filter( 'fetch_value', \&my_filter_fetch_value );

ok(
	($db->{key1} eq "value1") && 
	($db->{key2} eq "value2")
);

##
# Try fetching keys as well as values
##
my $first_key = $db->first_key();
my $next_key = $db->next_key($first_key);

ok(
	(($first_key eq "key1") || ($first_key eq "key2")) && 
	(($next_key eq "key1") || ($next_key eq "key2"))
);

##
# Now clear all filters, and make sure all is unfiltered
##
$db->set_filter( 'store_key', undef );
$db->set_filter( 'store_value', undef );
$db->set_filter( 'fetch_key', undef );
$db->set_filter( 'fetch_value', undef );

ok(
	($db->{MYFILTERkey1} eq "MYFILTERvalue1") && 
	($db->{MYFILTERkey2} eq "MYFILTERvalue2")
);

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);

sub my_filter_store_key { return 'MYFILTER' . $_[0]; }
sub my_filter_store_value { return 'MYFILTER' . $_[0]; }

sub my_filter_fetch_key { $_[0] =~ s/^MYFILTER//; return $_[0]; }
sub my_filter_fetch_value { $_[0] =~ s/^MYFILTER//; return $_[0]; }
