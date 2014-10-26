##
# DBM::Deep Test
##
use strict;
use Test::More tests => 17;
use t::common qw( new_fh );

use_ok( 'DBM::Deep' );

my ($fh, $filename) = new_fh();
my $db = DBM::Deep->new(
	file => $filename,
);

ok( !$db->set_filter( 'floober', sub {} ), "floober isn't a value filter key" );

##
# First try store filters only (values will be unfiltered)
##
ok( $db->set_filter( 'store_key', \&my_filter_store_key ), "set the store_key filter" );
ok( $db->set_filter( 'store_value', \&my_filter_store_value ), "set the store_value filter" );

$db->{key1} = "value1";
$db->{key2} = "value2";

is($db->{key1}, "MYFILTERvalue1", "The value for key1 was filtered correctly" );
is($db->{key2}, "MYFILTERvalue2", "The value for key2 was filtered correctly" );

##
# Now try fetch filters as well
##
ok( $db->set_filter( 'fetch_key', \&my_filter_fetch_key ), "Set the fetch_key filter" );
ok( $db->set_filter( 'fetch_value', \&my_filter_fetch_value), "Set the fetch_value filter" );

is($db->{key1}, "value1", "Fetchfilters worked right");
is($db->{key2}, "value2", "Fetchfilters worked right");

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
ok( $db->set_filter( 'store_key', undef ), "Unset store_key filter" );
ok( $db->set_filter( 'store_value', undef ), "Unset store_value filter" );
ok( $db->set_filter( 'fetch_key', undef ), "Unset fetch_key filter" );
ok( $db->set_filter( 'fetch_value', undef ), "Unset fetch_value filter" );

is($db->{MYFILTERkey1}, "MYFILTERvalue1");
is($db->{MYFILTERkey2}, "MYFILTERvalue2");

sub my_filter_store_key { return 'MYFILTER' . $_[0]; }
sub my_filter_store_value { return 'MYFILTER' . $_[0]; }

sub my_filter_fetch_key { $_[0] =~ s/^MYFILTER//; return $_[0]; }
sub my_filter_fetch_value { $_[0] =~ s/^MYFILTER//; return $_[0]; }
