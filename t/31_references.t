##
# DBM::Deep Test
##
use strict;
use Test::More tests => 16;
use Test::Exception;
use t::common qw( new_fh );

use_ok( 'DBM::Deep' );

my ($fh, $filename) = new_fh();
my $db = DBM::Deep->new( $filename );

my %hash = (
    foo => 1,
    bar => [ 1 .. 3 ],
    baz => { a => 42 },
);

$db->{hash} = \%hash;
isa_ok( tied(%hash), 'DBM::Deep::Hash' );

is( $db->{hash}{foo}, 1 );
is_deeply( $db->{hash}{bar}, [ 1 .. 3 ] );
is_deeply( $db->{hash}{baz}, { a => 42 } );

$hash{foo} = 2;
is( $db->{hash}{foo}, 2 );

$hash{bar}[1] = 90;
is( $db->{hash}{bar}[1], 90 );

$hash{baz}{b} = 33;
is( $db->{hash}{baz}{b}, 33 );

my @array = (
    1, [ 1 .. 3 ], { a => 42 },
);

$db->{array} = \@array;
isa_ok( tied(@array), 'DBM::Deep::Array' );

is( $db->{array}[0], 1 );
is_deeply( $db->{array}[1], [ 1 .. 3 ] );
is_deeply( $db->{array}[2], { a => 42 } );

$array[0] = 2;
is( $db->{array}[0], 2 );

$array[1][2] = 9;
is( $db->{array}[1][2], 9 );

$array[2]{b} = 'floober';
is( $db->{array}[2]{b}, 'floober' );

my %hash2 = ( abc => [ 1 .. 3 ] );
$array[3] = \%hash2;
SKIP: {
    skip "Internal references are not supported right now", 1;
    $hash2{ def } = \%hash;

    is( $array[3]{def}{foo}, 2 );
}