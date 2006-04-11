##
# DBM::Deep Test
##
use strict;
use Test::More tests => 7;
use Test::Exception;

use_ok( 'DBM::Deep' );

unlink 't/test.db';
my $db = DBM::Deep->new( 't/test.db' );

{
    {
        package My::Tie::Hash;

        sub TIEHASH {
            my $class = shift;

            return bless {
            }, $class;
        }
    }

    my %hash;
    tie %hash, 'My::Tie::Hash';
    isa_ok( tied(%hash), 'My::Tie::Hash' );

    throws_ok {
        $db->{foo} = \%hash;
    } qr/Cannot store a tied value/, "Cannot store tied hashes";
}

{
    {
        package My::Tie::Array;

        sub TIEARRAY {
            my $class = shift;

            return bless {
            }, $class;
        }

        sub FETCHSIZE { 0 }
    }

    my @array;
    tie @array, 'My::Tie::Array';
    isa_ok( tied(@array), 'My::Tie::Array' );

    throws_ok {
        $db->{foo} = \@array;
    } qr/Cannot store a tied value/, "Cannot store tied arrays";
}

    {
        package My::Tie::Scalar;

        sub TIESCALAR {
            my $class = shift;

            return bless {
            }, $class;
        }
    }

    my $scalar;
    tie $scalar, 'My::Tie::Scalar';
    isa_ok( tied($scalar), 'My::Tie::Scalar' );

throws_ok {
    $db->{foo} = \$scalar;
} qr/Storage of variables of type 'SCALAR' is not supported/, "Cannot store scalar references, let alone tied scalars";
